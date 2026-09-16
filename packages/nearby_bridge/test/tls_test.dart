import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:test/test.dart';

void main() {
  late TlsIdentity identity;
  late SecureServerSocket server;
  final sockets = <SecureSocket>[];
  final errors = <Object>[];
  final received = <String>[];

  setUpAll(() async {
    identity = await TlsIdentity.generate();
  });
  setUp(() async {
    errors.clear();
    received.clear();
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.createServerContext(),
      supportedProtocols: [nearbyAlpn],
    );
    server.listen(
      (socket) {
        sockets.add(socket);
        socket.listen(
          (bytes) {
            received.add(utf8.decode(bytes));
            socket.add(bytes);
          },
          onError: (Object error) {
            errors.add(error);
          },
        );
      },
      onError: (Object error) {
        errors.add(error);
      },
    );
  });
  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await server.close();
  });

  test(
    'generated RSA-2048 identity completes real TLS + bounded JSON roundtrip',
    () async {
      final client = await connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: server.port,
        certificateSha256: identity.certificateSha256,
      );
      addTearDown(client.destroy);
      expect(client.selectedProtocol, nearbyAlpn);
      expect(client.peerCertificate, isNotNull);
      final response = client
          .cast<List<int>>()
          .transform(const JsonLineDecoder())
          .first;
      client.add(
        const NearbyFrameCodec().encode(
          NearbyFrame({'v': 1, 'type': 'ping', 'seq': 1}),
        ),
      );
      expect(
        (await response.timeout(const Duration(seconds: 5))).fields['seq'],
        1,
      );
      expect(received.single, contains('"type":"ping"'));
      expect(errors, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'wrong out-of-band certificate pin fails before application bytes',
    () async {
      await expectLater(
        connectPinnedTls(
          address: InternetAddress.loopbackIPv4,
          port: server.port,
          certificateSha256: List.filled(32, 0),
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(received, isEmpty);
    },
  );

  test('plaintext command cannot enter a TLS-only server', () async {
    final raw = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    addTearDown(raw.destroy);
    final done = Completer<void>();
    raw.listen(
      (_) {},
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    raw.add(utf8.encode('{"v":1,"type":"command","method":"playback.play"}\n'));
    await done.future.timeout(const Duration(seconds: 5));
    expect(received, isEmpty);
    expect(errors, isNotEmpty);
  });

  test('TLS peer without companion ALPN is rejected after handshake', () async {
    final other = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.createServerContext()..setAlpnProtocols(['unrelated/1'], true),
    );
    final subscription = other.listen(
      (s) => s.destroy(),
      onError: (Object _) {},
    );
    addTearDown(() async {
      await subscription.cancel();
      await other.close();
    });
    await expectLater(
      connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: other.port,
        certificateSha256: identity.certificateSha256,
      ),
      throwsA(anyOf(isA<NearbyException>(), isA<HandshakeException>())),
    );
  });

  test(
    'expired certificate is rejected even with matching pin',
    () async {
      final expired = await TlsIdentity.generate(
        notBefore: DateTime.now().toUtc().subtract(const Duration(days: 3)),
        days: 1,
      );
      final other = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        expired.createServerContext(),
        supportedProtocols: [nearbyAlpn],
      );
      final subscription = other.listen(
        (s) => s.destroy(),
        onError: (Object _) {},
      );
      addTearDown(() async {
        await subscription.cancel();
        await other.close();
      });
      await expectLater(
        connectPinnedTls(
          address: InternetAddress.loopbackIPv4,
          port: other.port,
          certificateSha256: expired.certificateSha256,
        ),
        throwsA(isA<HandshakeException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
