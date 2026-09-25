import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_share.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_constants.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_endpoints.dart';

void main() {
  const sentence = 'sleepy-otter-counts-cozy-stars';

  group('encodeShareCode', () {
    test('default server + port stays the bare sentence', () {
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 8995),
        sentence,
      );
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 8995),
        isNot(contains('@')),
      );
    });

    test('custom server carries the port even when it is the default', () {
      // The explicit port is the unambiguous marker, so it's always present on a
      // non-default code (a colon never appears in a magic sentence).
      expect(
        encodeShareCode(room: sentence, server: 'cozy.example.net', port: 8999),
        '$sentence@cozy.example.net:8999',
      );
    });

    test('custom server + port appends @host:port', () {
      expect(
        encodeShareCode(room: sentence, server: 'cozy.example.net', port: 9000),
        '$sentence@cozy.example.net:9000',
      );
    });

    test('custom port on the default host still carries the port', () {
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 8999),
        '$sentence@syncplay.pl:8999',
      );
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 9000),
        '$sentence@syncplay.pl:9000',
      );
    });

    test('an IPv6 literal host is bracketed', () {
      expect(
        encodeShareCode(room: sentence, server: '2001:db8::1', port: 8999),
        '$sentence@[2001:db8::1]:8999',
      );
      expect(
        encodeShareCode(room: sentence, server: '2001:db8::1', port: 9000),
        '$sentence@[2001:db8::1]:9000',
      );
    });

    test('a bare single-label host carries the port', () {
      expect(
        encodeShareCode(room: sentence, server: 'myserver', port: 8999),
        '$sentence@myserver:8999',
      );
    });
  });

  group('parseShareCode — backward compatibility', () {
    test('a bare magic sentence is room-only', () {
      final r = parseShareCode(sentence);
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, isNull);
      expect(r.port, isNull);
    });

    test('an old room-only code (happy-cat-11) is room-only', () {
      final r = parseShareCode('happy-cat-11');
      expect(r.isValid, isTrue);
      expect(r.room, 'happy-cat-11');
      expect(r.server, isNull);
      expect(r.port, isNull);
    });

    test('a folded private code joins verbatim', () {
      final r = parseShareCode('happy-cat-11-k3pn');
      expect(r.isValid, isTrue);
      expect(r.room, 'happy-cat-11-k3pn');
      expect(r.server, isNull);
    });

    // A legacy/manual room name that merely contains `@` (no endpoint-like tail)
    // must still join as that exact room, not be split into room + server.
    for (final legacy in const [
      'movie@home', // single-label tail, not a server
      'movie@example.com', // dotted but no port -> still a room name, not a host
      'sleepy-otter-counts-cozy-stars@cozy.example.net', // port-less, verbatim
      'sleepy-otter-counts-cozy-stars@host@extra', // two @, no endpoint
      'sleepy-otter-counts-cozy-stars@', // trailing @
      '@cozy.example.net', // empty room half
    ]) {
      test('keeps the room name "$legacy" verbatim', () {
        final r = parseShareCode(legacy);
        expect(r.isValid, isTrue);
        expect(r.room, legacy);
        expect(r.server, isNull);
        expect(r.port, isNull);
      });
    }
  });

  group('parseShareCode — structured codes', () {
    test('room@host:port yields room + server + port', () {
      final r = parseShareCode('$sentence@cozy.example.net:9000');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });

    test('surrounding whitespace is trimmed', () {
      final r = parseShareCode('  $sentence@cozy.example.net:9000  ');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });

    test('a bracketed IPv6 literal parses host without the brackets', () {
      final r = parseShareCode('$sentence@[2001:db8::1]');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, '2001:db8::1');
      expect(r.port, isNull);
    });

    test('a bracketed IPv6 literal with a port keeps both', () {
      final r = parseShareCode('$sentence@[2001:db8::1]:9000');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, '2001:db8::1');
      expect(r.port, 9000);
    });

    test('splits on the last @ so a room name containing @ survives', () {
      // Re-sharing a room joined as `movie@example.com` from a custom server.
      final r = parseShareCode('movie@example.com@cozy.example.net:9000');
      expect(r.isValid, isTrue);
      expect(r.room, 'movie@example.com');
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });

    test('a room name with @ round-trips through encode → parse', () {
      final encoded = encodeShareCode(
        room: 'movie@example.com',
        server: 'cozy.example.net',
        port: 9000,
      );
      expect(encoded, 'movie@example.com@cozy.example.net:9000');
      final r = parseShareCode(encoded);
      expect(r.room, 'movie@example.com');
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });
  });

  group('parseShareCode — round-trips with encodeShareCode', () {
    for (final c in const [
      ['syncplay.pl', 8999],
      ['syncplay.pl', 8995],
      ['cozy.example.net', 8999],
      ['cozy.example.net', 9000],
      ['syncplay.pl', 9000],
      ['2001:db8::1', 8999], // IPv6, bracketed by the encoder
      ['2001:db8::1', 9000],
      ['myserver', 8999], // bare single-label host, port pinned by the encoder
    ]) {
      final server = c[0] as String;
      final port = c[1] as int;
      test('$server:$port survives encode → parse', () {
        final encoded = encodeShareCode(
          room: sentence,
          server: server,
          port: port,
        );
        final parsed = parseShareCode(encoded);
        expect(parsed.isValid, isTrue);
        expect(parsed.room, sentence);
        // A null server/port from the parser means "use the default" — which is
        // exactly what was encoded, so reconstruct before comparing.
        expect(parsed.server ?? 'syncplay.pl', server);
        expect(parsed.port ?? SyncplayConstants.publicServerPort, port);
      });
    }
  });

  // Only a tail that clearly looks like a *broken* endpoint errors; an
  // ambiguous tail falls back to a verbatim room join (covered above).
  group('parseShareCode — malformed gets clear feedback', () {
    for (final bad in const [
      '$sentence@cozy.example.net:abc', // non-numeric port
      '$sentence@cozy.example.net:70000', // port out of range
      '$sentence@cozy.example.net:0', // port out of range
      '$sentence@myserver:abc', // single-label host, garbled port
      '$sentence@myserver:', // single-label host, empty port
      '$sentence@cozy example.net:9000', // whitespace in host
      '$sentence@[2001:db8::1', // unclosed IPv6 bracket
      '$sentence@[]:9000', // empty bracketed host
      '$sentence@2001:db8::1', // IPv6 must be bracketed to share
    ]) {
      test('rejects "$bad"', () {
        final r = parseShareCode(bad);
        expect(r.isValid, isFalse);
        expect(r.error, malformedShareCodeMessage);
      });
    }
  });

  group('a discovered endpoint reaches the joiner intact (#234)', () {
    // Two peers only meet if the code answers "where is this room" the same way
    // on both machines. Whatever the host's discovery settled on has to survive
    // encode -> paste -> parse exactly, and the default has to stay the bare
    // sentence, so old codes and older builds still line up.
    for (final endpoint in kPublicSyncplayEndpoints) {
      test('$endpoint round-trips', () {
        final code = encodeShareCode(
          room: sentence,
          server: endpoint.host,
          port: endpoint.port,
        );
        final parsed = parseShareCode(code);

        expect(parsed.isValid, isTrue);
        expect(parsed.room, sentence);
        expect(
          code.contains('@'),
          endpoint != kPublicSyncplayEndpoints.first,
          reason: 'only a moved room needs to name where it went',
        );
        expect(parsed.server ?? SyncplayConstants.defaultServer, endpoint.host);
        expect(
          parsed.port ?? SyncplayConstants.publicServerPort,
          endpoint.port,
        );
      });
    }
  });
}
