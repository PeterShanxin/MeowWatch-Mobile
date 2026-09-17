import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_activity.dart';

void main() {
  SyncActivity? classify({
    required bool peerPaused,
    required bool localPaused,
    bool doSeek = false,
    Duration peerPos = const Duration(seconds: 100),
    Duration localPos = const Duration(seconds: 100),
    String? setBy = 'lin',
  }) => classifySyncActivity(
    global: PeerPlayState(
      position: peerPos,
      paused: peerPaused,
      doSeek: doSeek,
      setBy: setBy,
    ),
    localPaused: localPaused,
    localPosition: localPos,
  );

  test('pause flip → paused at peer position', () {
    final a = classify(peerPaused: true, localPaused: false);
    expect(a, isNotNull);
    expect(a!.kind, SyncActivityKind.paused);
    expect(a.username, 'lin');
    expect(a.position, const Duration(seconds: 100));
  });

  test('play flip → played', () {
    final a = classify(peerPaused: false, localPaused: true);
    expect(a!.kind, SyncActivityKind.played);
  });

  test('forward seek → seekedForward', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 500),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedForward);
    expect(a.position, const Duration(seconds: 500));
  });

  test('backward seek → seekedBack', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 30),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedBack);
  });

  test('micro-seek within noise threshold → null', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(milliseconds: 100600),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('drift rewind (no flip, no seek, ahead past threshold) → driftRewound '
      'at the room position (#98)', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      peerPos: const Duration(seconds: 80),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNotNull);
    expect(a!.kind, SyncActivityKind.driftRewound);
    // Lands on the room position, not where we drifted to.
    expect(a.position, const Duration(seconds: 80));
    expect(a.username, 'lin');
  });

  test(
    'drift correction is NOT classified as a deliberate seek-back (#98)',
    () {
      final drift = classify(
        peerPaused: false,
        localPaused: false,
        doSeek: false,
        peerPos: const Duration(seconds: 80),
        localPos: const Duration(seconds: 100),
      );
      final seekBack = classify(
        peerPaused: false,
        localPaused: false,
        doSeek: true,
        peerPos: const Duration(seconds: 80),
        localPos: const Duration(seconds: 100),
      );
      expect(drift!.kind, SyncActivityKind.driftRewound);
      expect(seekBack!.kind, SyncActivityKind.seekedBack);
    },
  );

  test('ahead but within the rewind threshold → null (no real correction)', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      peerPos: const Duration(seconds: 98),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('behind the room with no flip/seek → null (one-directional)', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      peerPos: const Duration(seconds: 100),
      localPos: const Duration(seconds: 80),
    );
    expect(a, isNull);
  });

  test(
    'drift rewind with no setter → null (ignored empty-room reset, #98)',
    () {
      final a = classify(
        peerPaused: false,
        localPaused: false,
        peerPos: const Duration(seconds: 0),
        localPos: const Duration(seconds: 100),
        setBy: null,
      );
      expect(a, isNull);
    },
  );

  test('unattributable (setBy null) → null', () {
    final a = classify(peerPaused: true, localPaused: false, setBy: null);
    expect(a, isNull);
  });

  group('classifyLocalActivity (issue #27 — announce our own actions)', () {
    SyncActivity? local({
      required bool doSeek,
      required bool paused,
      required bool wasPaused,
      Duration position = const Duration(seconds: 100),
      Duration previousPosition = const Duration(seconds: 100),
      String username = 'me',
    }) => classifyLocalActivity(
      doSeek: doSeek,
      paused: paused,
      wasPaused: wasPaused,
      position: position,
      previousPosition: previousPosition,
      username: username,
    );

    test('local pause flip → paused at our position', () {
      final a = local(doSeek: false, paused: true, wasPaused: false);
      expect(a!.kind, SyncActivityKind.paused);
      expect(a.username, 'me');
      expect(a.position, const Duration(seconds: 100));
    });

    test('local play flip → played', () {
      final a = local(doSeek: false, paused: false, wasPaused: true);
      expect(a!.kind, SyncActivityKind.played);
    });

    test('local forward seek → seekedForward at the landing position', () {
      final a = local(
        doSeek: true,
        paused: false,
        wasPaused: false,
        previousPosition: const Duration(seconds: 100),
        position: const Duration(seconds: 500),
      );
      expect(a!.kind, SyncActivityKind.seekedForward);
      expect(a.position, const Duration(seconds: 500));
    });

    test('local backward seek → seekedBack', () {
      final a = local(
        doSeek: true,
        paused: false,
        wasPaused: false,
        previousPosition: const Duration(seconds: 100),
        position: const Duration(seconds: 30),
      );
      expect(a!.kind, SyncActivityKind.seekedBack);
    });

    test('no flip and no seek → null (steady playback ticks stay silent)', () {
      final a = local(doSeek: false, paused: false, wasPaused: false);
      expect(a, isNull);
    });
  });
}
