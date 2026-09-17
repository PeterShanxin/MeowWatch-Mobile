import 'dart:convert';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('LAN addresses and prefixes', () {
    test('accepts only canonical private/link-local numeric IPv4', () {
      for (final ip in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.4.2',
        '169.254.1.2',
      ]) {
        expect(LanIpv4Address.parse(ip).toString(), ip);
      }
      for (final ip in [
        '127.0.0.1',
        '0.0.0.0',
        '8.8.8.8',
        '172.32.0.1',
        '172.15.1.1',
        '224.0.0.1',
        '255.255.255.255',
        '::ffff:192.168.0.1',
        '192.168.01.2',
        '192.168.1.256',
        '192.168.1',
        '3232235777',
        '0xc0.168.1.1',
        'desktop.local',
        '192.168.1.1\n',
      ]) {
        expect(
          () => LanIpv4Address.parse(ip),
          throwsA(isA<NearbyException>()),
          reason: ip,
        );
      }
    });
    test('requires actual subnet, excluding network and broadcast', () {
      final subnet = LanSubnet(
        localAddress: LanIpv4Address.parse('192.168.2.9'),
        prefixLength: 24,
      );
      subnet.requirePeer('192.168.2.200');
      for (final ip in [
        '192.168.3.1',
        '10.1.2.3',
        '192.168.2.0',
        '192.168.2.255',
      ]) {
        expect(() => subnet.requirePeer(ip), throwsA(isA<NearbyException>()));
      }
      for (final prefix in [0, 31, 32, 33]) {
        expect(
          () => LanSubnet(
            localAddress: subnet.localAddress,
            prefixLength: prefix,
          ),
          throwsA(isA<NearbyException>()),
        );
      }
    });
  });

  group('invitation', () {
    final invitation = PairingInvitation(
      desktopId: encodeBytes(List.filled(16, 1)),
      pairId: encodeBytes(List.filled(16, 2)),
      endpoint: LanEndpoint(
        address: LanIpv4Address.parse('192.168.1.10'),
        port: 41983,
      ),
      certificateSha256: List.filled(32, 3),
      pairSecret: List.generate(16, (i) => i),
    );
    test('QR and grouped manual fallback preserve all 128 bits', () {
      final restored = PairingInvitation.decodeQr(invitation.encodeQr());
      expect(restored.pairSecret, invitation.pairSecret);
      expect(restored.certificateSha256, invitation.certificateSha256);
      expect(restored.endpoint.port, 41983);
      expect(invitation.manualCode.length, 26);
      final grouped = invitation.manualCode.replaceAllMapped(
        RegExp('.{5}'),
        (m) => '${m[0]}-',
      );
      expect(decodeManualCode(grouped.toLowerCase()), invitation.pairSecret);
      expect(invitation.toString(), isNot(contains(invitation.manualCode)));
    });
    test(
      'rejects short codes, noncanonical trailing bits, arbitrary QR URLs',
      () {
        for (final code in ['123456', '0' * 25 + '1', 'I' * 26, '0' * 100]) {
          expect(() => decodeManualCode(code), throwsA(isA<NearbyException>()));
        }
        for (final qr in [
          'https://evil.test',
          '${invitation.encodeQr()}=',
          'meowwatch-pair:!',
        ]) {
          expect(
            () => PairingInvitation.decodeQr(qr),
            throwsA(isA<NearbyException>()),
          );
        }
      },
    );
    test('canonical IDs reject padding and alternate encodings', () {
      expect(
        () => decodeBytes('${invitation.pairId}=', 16),
        throwsA(isA<NearbyException>()),
      );
      expect(
        () => decodeBytes('A' * 21 + 'B', 16),
        throwsA(isA<NearbyException>()),
      );
    });
  });

  group('bounded wire', () {
    const codec = NearbyFrameCodec();
    NearbyFrame parse(String text) => codec.decode(utf8.encode(text));
    test('handles fragmented and concatenated real UTF-8 frames', () async {
      final a = codec.encode(
        NearbyFrame({'v': 1, 'type': 'chat.message', 'text': '你好🐱'}),
      );
      final b = codec.encode(NearbyFrame({'v': 1, 'type': 'ping', 'seq': 2}));
      final output = await Stream.fromIterable([
        a.sublist(0, a.length - 3),
        [...a.sublist(a.length - 3), ...b],
      ]).transform(const JsonLineDecoder()).toList();
      expect(output.map((f) => f.type), ['chat.message', 'ping']);
      expect(output.first.fields['text'], '你好🐱');
    });
    test(
      'rejects duplicate keys, malformed UTF8, deep nesting, oversized collections',
      () {
        for (final text in [
          '{"v":1,"v":1,"type":"ping"}',
          '{"v":1,"type":"ping","x":{"a":1,"a":2}}',
          '{"v":1,"type":"ping","x":${'[' * 14}0${']' * 14}}',
          '{"v":1,"type":"ping","x":[${List.filled(257, '0').join(',')}]}',
          '{"v":1,"type":"ping","x":1e309}',
          '{"v":1,"type":"ping","x":9007199254740992}',
          '{"v":1,"type":"ping","x":"\\ud800"}',
          '{"v":1,"type":"ping","x":"${'a' * 4097}"}',
          '{"v":1,"type":"ping",}',
          '{"v":1,"type":"ping"} trailing',
        ]) {
          expect(() => parse(text), throwsA(isA<NearbyException>()));
        }
        expect(() => codec.decode([0xff]), throwsA(isA<NearbyException>()));
        expect(
          () => parse('{"v":2,"type":"ping"}'),
          throwsA(isA<NearbyException>()),
        );
      },
    );
    test('no-LF overflow and EOF partial frame are terminal errors', () async {
      await expectLater(
        Stream.value(
          List.filled(maxFrameBytes + 1, 32),
        ).transform(const JsonLineDecoder()).toList(),
        throwsA(isA<NearbyException>()),
      );
      await expectLater(
        Stream<List<int>>.value(
          utf8.encode('{"v":1,"type":"ping"}'),
        ).transform(const JsonLineDecoder()).toList(),
        throwsA(isA<NearbyException>()),
      );
    });
    test('command bounds and sequence replay', () {
      NearbyFrame command(String method, Map<String, Object?> args) =>
          NearbyFrame({
            'v': 1,
            'type': 'command',
            'seq': 1,
            'id': 'a',
            'sessionEpoch': 'room',
            'method': method,
            'args': args,
          });
      final sequence = FrameSequence();
      final play = command('playback.play', {});
      sequence.accept(play);
      expect(() => sequence.accept(play), throwsA(isA<NearbyException>()));
      for (final position in [-1, 604800001, 1.2, double.nan]) {
        expect(
          () => command('playback.seek', {'positionMs': position}),
          throwsA(isA<NearbyException>()),
        );
      }
      expect(() => command('system.exec', {}), throwsA(isA<NearbyException>()));
      expect(
        () => command('chat.send', {'text': 'x' * 151}),
        throwsA(isA<NearbyException>()),
      );
      expect(
        () => command('chat.reaction', {'reaction': 'arbitrary'}),
        throwsA(isA<NearbyException>()),
      );
      expect(command('chat.send', {'text': '🐱' * 150}).type, 'command');
    });
  });
}
