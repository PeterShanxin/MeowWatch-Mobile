import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_discovery.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_endpoints.dart';

import '../../support/sync_fakes.dart';

const _a = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);
const _b = SyncplayEndpoint(host: 'syncplay.pl', port: 8996);
const _c = SyncplayEndpoint(host: 'syncplay.pl', port: 8997);
const _candidates = <SyncplayEndpoint>[_a, _b, _c];

/// Records every endpoint the walk actually attempted, in order, and answers
/// from a fixed set of working endpoints.
class _RecordingAttempt {
  _RecordingAttempt(this.working);

  final Set<SyncplayEndpoint> working;
  final List<SyncplayEndpoint> tried = <SyncplayEndpoint>[];

  Future<EndpointWalkDecision> call(SyncplayEndpoint endpoint) async {
    tried.add(endpoint);
    return working.contains(endpoint)
        ? EndpointWalkDecision.success
        : EndpointWalkDecision.next;
  }
}

SyncplayEndpointDiscovery _discovery(
  FakeEndpointSettings settings, {
  List<SyncplayEndpoint> candidates = _candidates,
}) {
  return SyncplayEndpointDiscovery(settings: settings, candidates: candidates);
}

Future<SyncplayEndpoint?> _walk(
  SyncplayEndpointDiscovery discovery,
  _RecordingAttempt attempt, {
  SyncplayEndpoint? preferred,
}) {
  return discovery.walk(preferred: preferred, attempt: attempt.call);
}

void main() {
  group('remembered endpoint', () {
    test('is tried first and short-circuits the scan', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, _c.toString());
      final attempt = _RecordingAttempt({_a, _c});

      final resolved = await _walk(_discovery(settings), attempt);

      expect(resolved, _c);
      expect(
        attempt.tried,
        [_c],
        reason: 'a working remembered endpoint must not cost a scan',
      );
    });

    test('is replaced when it no longer answers', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, _c.toString());
      final attempt = _RecordingAttempt({_b});

      final resolved = await _walk(_discovery(settings), attempt);

      expect(resolved, _b);
      expect(attempt.tried, [_c, _a, _b]);
      expect(await settings.get(kSyncplayEndpointSettingKey), _b.toString());
    });

    test('is ignored when it is no longer a curated candidate', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, 'retired.example:8995');
      final attempt = _RecordingAttempt({_a});

      final resolved = await _walk(_discovery(settings), attempt);

      expect(resolved, _a);
      expect(
        attempt.tried,
        [_a],
        reason: 'the curated list is the authority on what may be dialled',
      );
    });

    test('is ignored when the stored value is malformed', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, 'not-an-endpoint');
      final attempt = _RecordingAttempt({_a});

      expect(await _walk(_discovery(settings), attempt), _a);
      expect(attempt.tried, [_a]);
    });
  });

  group('scanning', () {
    test('falls through to the first candidate that answers', () async {
      final settings = FakeEndpointSettings();
      final attempt = _RecordingAttempt({_c});

      final resolved = await _walk(_discovery(settings), attempt);

      expect(resolved, _c);
      expect(attempt.tried, [_a, _b, _c]);
    });

    test('stops walking once a winner is found', () async {
      final settings = FakeEndpointSettings();
      final attempt = _RecordingAttempt({_b, _c});

      expect(await _walk(_discovery(settings), attempt), _b);
      expect(attempt.tried, [_a, _b]);
    });

    test('persists the winner', () async {
      final settings = FakeEndpointSettings();
      final attempt = _RecordingAttempt({_b});

      await _walk(_discovery(settings), attempt);

      expect(await settings.get(kSyncplayEndpointSettingKey), _b.toString());
    });

    test(
      'returns null and remembers nothing when every candidate fails',
      () async {
        final settings = FakeEndpointSettings();
        final attempt = _RecordingAttempt(const {});

        expect(await _walk(_discovery(settings), attempt), isNull);
        expect(attempt.tried, [_a, _b, _c]);
        expect(await settings.get(kSyncplayEndpointSettingKey), isNull);
      },
    );

    test(
      'leaves a previously remembered endpoint alone when nothing answers',
      () async {
        final settings = FakeEndpointSettings();
        await settings.set(kSyncplayEndpointSettingKey, _c.toString());
        final attempt = _RecordingAttempt(const {});

        expect(await _walk(_discovery(settings), attempt), isNull);
        expect(await settings.get(kSyncplayEndpointSettingKey), _c.toString());
      },
    );

    test('a Hello that refuses the room does not hop', () async {
      final settings = FakeEndpointSettings();
      final tried = <SyncplayEndpoint>[];

      final resolved = await _discovery(settings).walk(
        attempt: (endpoint) async {
          tried.add(endpoint);
          return EndpointWalkDecision.stop;
        },
      );

      expect(resolved, isNull);
      expect(tried, [_a], reason: 'hopping would split two peers');
    });
  });

  group('preferred endpoint (a room that already lives somewhere)', () {
    test('is tried before anything else', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, _a.toString());
      final attempt = _RecordingAttempt({_a, _c});

      final resolved = await _walk(
        _discovery(settings),
        attempt,
        preferred: _c,
      );

      expect(resolved, _c);
      expect(attempt.tried, [_c]);
    });

    test(
      'falls back down the shared list, skipping the remembered winner',
      () async {
        // Two peers on the same dead room must not diverge just because their
        // remembered winners differ, so the remembered endpoint is not consulted
        // when a room already has an address.
        final settings = FakeEndpointSettings();
        await settings.set(kSyncplayEndpointSettingKey, _c.toString());
        final attempt = _RecordingAttempt({_a, _c});

        final resolved = await _walk(
          _discovery(settings),
          attempt,
          preferred: _b,
        );

        expect(resolved, _a);
        expect(attempt.tried, [_b, _a]);
      },
    );

    test('is never dialled when it is not a curated candidate', () async {
      // A self-hosted server must never be reached through discovery; the
      // caller pins those instead of asking for a scan.
      final settings = FakeEndpointSettings();
      final attempt = _RecordingAttempt({_a});
      const selfHosted = SyncplayEndpoint(host: 'cozy.example.net', port: 8999);

      await _walk(_discovery(settings), attempt, preferred: selfHosted);

      expect(attempt.tried, isNot(contains(selfHosted)));
    });
  });

  test('a settings write failure does not fail the connect', () async {
    final attempt = _RecordingAttempt({_a});
    final discovery = SyncplayEndpointDiscovery(
      settings: _ThrowingEndpointSettings(),
      candidates: _candidates,
    );

    expect(await _walk(discovery, attempt), _a);
  });
}

class _ThrowingEndpointSettings implements EndpointSettings {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async =>
      throw StateError('disk full');
}
