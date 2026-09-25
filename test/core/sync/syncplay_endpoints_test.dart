import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_constants.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_endpoints.dart';

void main() {
  group('SyncplayEndpoint', () {
    test('round-trips through its persisted form', () {
      const endpoint = SyncplayEndpoint(host: 'syncplay.pl', port: 8997);

      expect(endpoint.toString(), 'syncplay.pl:8997');
      expect(SyncplayEndpoint.tryParse(endpoint.toString()), endpoint);
    });

    test('compares by value', () {
      expect(
        const SyncplayEndpoint(host: 'a', port: 1),
        const SyncplayEndpoint(host: 'a', port: 1),
      );
      expect(
        const SyncplayEndpoint(host: 'a', port: 1),
        isNot(const SyncplayEndpoint(host: 'a', port: 2)),
      );
    });

    test('rejects anything that is not host:port with a real port', () {
      for (final bad in <String>[
        '',
        'syncplay.pl',
        'syncplay.pl:',
        ':8995',
        'syncplay.pl:0',
        'syncplay.pl:65536',
        'syncplay.pl:eight',
        '2001:db8::1:8995',
        'syncplay pl:8995',
      ]) {
        expect(
          SyncplayEndpoint.tryParse(bad),
          isNull,
          reason: 'must not dial "$bad"',
        );
      }
    });
  });

  group('the curated candidate list', () {
    test('starts at the endpoint a bare share code means', () {
      // A code with no `@host:port` says "the default public server", and both
      // peers must read that the same way — so the first candidate has to stay
      // the endpoint the share-code encoder treats as bare.
      expect(
        kPublicSyncplayEndpoints.first,
        const SyncplayEndpoint(
          host: SyncplayConstants.defaultServer,
          port: SyncplayConstants.publicServerPort,
        ),
      );
    });

    test('holds no duplicates', () {
      expect(
        kPublicSyncplayEndpoints.toSet().length,
        kPublicSyncplayEndpoints.length,
      );
    });

    test('recognises its own entries and nothing else', () {
      for (final endpoint in kPublicSyncplayEndpoints) {
        expect(isPublicSyncplayCandidate(endpoint), isTrue);
      }
      expect(
        isPublicSyncplayCandidate(
          const SyncplayEndpoint(host: 'cozy.example.net', port: 8999),
        ),
        isFalse,
      );
      expect(
        isPublicSyncplayCandidate(
          const SyncplayEndpoint(host: 'syncplay.pl', port: 9000),
        ),
        isFalse,
      );
    });
  });
}
