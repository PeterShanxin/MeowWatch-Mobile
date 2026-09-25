import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/auto_pause.dart';

void main() {
  group('decideAutoPause', () {
    test('fires on the healthy -> unhealthy edge while playing', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: false, isPlaying: true),
        isTrue,
      );
    });

    test('does not fire when already paused', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: false, isPlaying: false),
        isFalse,
      );
    });

    test('does not fire when sync stays healthy', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: true, isPlaying: true),
        isFalse,
      );
    });

    test('does not fire when it was already unhealthy (no edge)', () {
      // e.g. user deliberately hits play again while alone — stay playing.
      expect(
        decideAutoPause(wasHealthy: false, nowHealthy: false, isPlaying: true),
        isFalse,
      );
    });

    test('does not fire when sync is recovering (unhealthy -> healthy)', () {
      expect(
        decideAutoPause(wasHealthy: false, nowHealthy: true, isPlaying: true),
        isFalse,
      );
    });
  });

  group('SyncHealth.healthy', () {
    test('healthy only when connected AND a peer is present', () {
      expect(const SyncHealth(connected: true, hasPeer: true).healthy, isTrue);
      expect(
        const SyncHealth(connected: true, hasPeer: false).healthy,
        isFalse,
      );
      expect(
        const SyncHealth(connected: false, hasPeer: true).healthy,
        isFalse,
      );
      expect(
        const SyncHealth(connected: false, hasPeer: false).healthy,
        isFalse,
      );
    });
  });

  group('autoPauseCause', () {
    test('peer left: still connected but the room is now empty', () {
      expect(
        autoPauseCause(connected: true, hasPeer: false),
        AutoPauseCause.peerLeft,
      );
    });

    test('connection lost: disconnected, regardless of peer flag', () {
      expect(
        autoPauseCause(connected: false, hasPeer: false),
        AutoPauseCause.connectionLost,
      );
      // A stale "peer present" flag on a dropped socket is still a connection
      // loss, not a leave — never claim someone left.
      expect(
        autoPauseCause(connected: false, hasPeer: true),
        AutoPauseCause.connectionLost,
      );
    });
  });

  group('autoPauseMessage', () {
    test('peer left names the friend who left', () {
      expect(
        autoPauseMessage(cause: AutoPauseCause.peerLeft, peerName: 'lin'),
        'lin left, auto-paused',
      );
    });

    test('peer left falls back to "Friend" when the name is unknown', () {
      expect(
        autoPauseMessage(cause: AutoPauseCause.peerLeft, peerName: null),
        'Friend left, auto-paused',
      );
    });

    test(
      'connection loss never claims a peer left, even with a stale name',
      () {
        expect(
          autoPauseMessage(
            cause: AutoPauseCause.connectionLost,
            peerName: 'lin',
          ),
          'Paused — lost sync with your friend',
        );
      },
    );
  });
}
