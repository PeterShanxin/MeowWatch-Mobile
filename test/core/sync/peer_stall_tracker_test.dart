import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_stall_tracker.dart';

void main() {
  group('PeerStallTracker', () {
    test('flags a peer that claims playing but never advances', () {
      final tracker = PeerStallTracker(stallTicks: 3);
      // First heartbeat seeds the baseline; it is never a stall on its own.
      tracker.update(
        position: const Duration(seconds: 500),
        paused: false,
        doSeek: false,
      );
      expect(tracker.stalled, isFalse);
      // Successive playing heartbeats with no real advancement → stalled.
      for (var i = 0; i < 3; i++) {
        tracker.update(
          position: const Duration(seconds: 500),
          paused: false,
          doSeek: false,
        );
      }
      expect(tracker.stalled, isTrue);
    });

    test('tolerates frozen-engine position wobble (still flags a stall)', () {
      // A frozen mpv reports small noise around the stuck frame (the field log
      // wobbled ~±1s). Net advancement stays ~0, so it must still be a stall.
      final tracker = PeerStallTracker(stallTicks: 3);
      const wobble = [500, 501, 500, 500, 501, 500];
      for (final p in wobble) {
        tracker.update(
          position: Duration(seconds: p),
          paused: false,
          doSeek: false,
        );
      }
      expect(
        tracker.stalled,
        isTrue,
        reason: 'sub-threshold wobble is not real advancement',
      );
    });

    test('does not flag a normally-advancing peer', () {
      final tracker = PeerStallTracker(stallTicks: 3);
      for (var p = 500; p < 520; p++) {
        tracker.update(
          position: Duration(seconds: p),
          paused: false,
          doSeek: false,
        );
        expect(tracker.stalled, isFalse);
      }
    });

    test('clears the stall once the peer starts advancing again', () {
      final tracker = PeerStallTracker(stallTicks: 3);
      for (var i = 0; i < 5; i++) {
        tracker.update(
          position: const Duration(seconds: 500),
          paused: false,
          doSeek: false,
        );
      }
      expect(tracker.stalled, isTrue);
      // The peer recovers and jumps well past the stuck frame.
      tracker.update(
        position: const Duration(seconds: 506),
        paused: false,
        doSeek: false,
      );
      expect(tracker.stalled, isFalse);
    });

    test('a paused peer is not a stall', () {
      final tracker = PeerStallTracker(stallTicks: 2);
      for (var i = 0; i < 5; i++) {
        tracker.update(
          position: const Duration(seconds: 500),
          paused: true,
          doSeek: false,
        );
      }
      expect(
        tracker.stalled,
        isFalse,
        reason: 'a deliberately paused peer is not frozen',
      );
    });

    test('a backward position jump (reload/seek-back) re-baselines', () {
      // A file reload or a seek-back that skipped the doSeek flag drops the
      // peer's position far below the baseline — that is a reposition, not a
      // frozen frame, so it must re-baseline rather than count toward a stall.
      final tracker = PeerStallTracker(stallTicks: 3);
      tracker.update(
        position: const Duration(seconds: 500),
        paused: false,
        doSeek: false,
      );
      tracker.update(
        position: const Duration(seconds: 0),
        paused: false,
        doSeek: false,
      );
      expect(
        tracker.stalled,
        isFalse,
        reason: 'a backward jump is a reposition, not a stuck frame',
      );
      // Playing forward from the new baseline (clear > advanceEpsilon steps) keeps
      // re-baselining, so it never trips the stall.
      tracker.update(
        position: const Duration(seconds: 3),
        paused: false,
        doSeek: false,
      );
      tracker.update(
        position: const Duration(seconds: 6),
        paused: false,
        doSeek: false,
      );
      expect(tracker.stalled, isFalse);
    });

    test('an explicit peer seek resets the stall baseline', () {
      final tracker = PeerStallTracker(stallTicks: 2);
      for (var i = 0; i < 4; i++) {
        tracker.update(
          position: const Duration(seconds: 500),
          paused: false,
          doSeek: false,
        );
      }
      expect(tracker.stalled, isTrue);
      // A real seek (doSeek) is an intentional reposition, not a freeze.
      tracker.update(
        position: const Duration(seconds: 800),
        paused: false,
        doSeek: true,
      );
      expect(tracker.stalled, isFalse);
    });
  });
}
