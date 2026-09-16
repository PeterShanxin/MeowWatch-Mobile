import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_activity_throttle.dart';

void main() {
  SyncActivity activity(SyncActivityKind kind, int seconds) => SyncActivity(
    kind: kind,
    username: 'lin',
    position: Duration(seconds: seconds),
  );

  // fake_async keeps the debounce deterministic — no wall-clock timers, so the
  // suite never flakes on a slow CI runner.
  void withThrottle(
    void Function(FakeAsync, SyncActivityThrottle, List<SyncActivity>) body,
  ) {
    fakeAsync((async) {
      final throttle = SyncActivityThrottle(
        window: const Duration(milliseconds: 40),
      );
      final out = <SyncActivity>[];
      throttle.stream.listen(out.add);
      body(async, throttle, out);
      throttle.dispose();
      async.flushMicrotasks();
    });
  }

  test('pause/play pass straight through (no debounce)', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.paused, 12));
      throttle.add(activity(SyncActivityKind.played, 12));
      async.flushMicrotasks();
      expect(out.map((a) => a.kind), [
        SyncActivityKind.paused,
        SyncActivityKind.played,
      ]);
    });
  });

  test('a burst of seeks collapses into a single final notification (#26)', () {
    withThrottle((async, throttle, out) {
      // Simulate scrubbing: many rapid seek events, each within the window.
      for (var s = 1; s <= 5; s++) {
        throttle.add(activity(SyncActivityKind.seekedForward, s * 10));
        async.elapse(const Duration(milliseconds: 10));
      }
      // Nothing emitted yet — still inside the debounce window.
      expect(out, isEmpty);
      async.elapse(const Duration(milliseconds: 40));
      expect(out, hasLength(1));
      expect(out.single.kind, SyncActivityKind.seekedForward);
      // The LAST seek (landing position) is the one that survives.
      expect(out.single.position, const Duration(seconds: 50));
    });
  });

  test('a lone seek is emitted once the window elapses', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.seekedBack, 30));
      expect(out, isEmpty);
      async.elapse(const Duration(milliseconds: 40));
      expect(out, hasLength(1));
      expect(out.single.kind, SyncActivityKind.seekedBack);
    });
  });

  test('a pause arriving mid-scrub flushes the pending seek first', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.seekedForward, 20));
      throttle.add(activity(SyncActivityKind.paused, 20));
      async.flushMicrotasks();
      // Seek flushed immediately ahead of the pause, preserving order.
      expect(out.map((a) => a.kind), [
        SyncActivityKind.seekedForward,
        SyncActivityKind.paused,
      ]);
    });
  });

  test('a pending seek is dropped on dispose (no late emission)', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.seekedForward, 10));
      throttle.dispose();
      async.elapse(const Duration(milliseconds: 40));
      expect(out, isEmpty);
    });
  });

  test('first drift correction passes straight through (#98)', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.driftRewound, 80));
      async.flushMicrotasks();
      expect(out, hasLength(1));
      expect(out.single.kind, SyncActivityKind.driftRewound);
    });
  });

  test('a repeated drift inside the cooldown is dropped (#98)', () {
    fakeAsync((async) {
      final throttle = SyncActivityThrottle(
        window: const Duration(milliseconds: 40),
        driftCooldown: const Duration(seconds: 8),
      );
      final out = <SyncActivity>[];
      throttle.stream.listen(out.add);

      throttle.add(activity(SyncActivityKind.driftRewound, 80));
      async.elapse(const Duration(seconds: 3));
      throttle.add(activity(SyncActivityKind.driftRewound, 70));
      async.flushMicrotasks();
      // Only the first survives; the second is inside the cooldown.
      expect(out, hasLength(1));
      expect(out.single.position, const Duration(seconds: 80));

      // Once the cooldown elapses, a fresh correction gets through again.
      async.elapse(const Duration(seconds: 6));
      throttle.add(activity(SyncActivityKind.driftRewound, 60));
      async.flushMicrotasks();
      expect(out, hasLength(2));
      expect(out.last.position, const Duration(seconds: 60));

      throttle.dispose();
      async.flushMicrotasks();
    });
  });

  test(
    'drift flushes a pending seek ahead of itself, preserving order (#98)',
    () {
      withThrottle((async, throttle, out) {
        throttle.add(activity(SyncActivityKind.seekedForward, 20));
        throttle.add(activity(SyncActivityKind.driftRewound, 18));
        async.flushMicrotasks();
        expect(out.map((a) => a.kind), [
          SyncActivityKind.seekedForward,
          SyncActivityKind.driftRewound,
        ]);
      });
    },
  );

  test('clearPending drops a queued seek so it cannot fire later', () {
    withThrottle((async, throttle, out) {
      throttle.add(activity(SyncActivityKind.seekedForward, 20));
      throttle.clearPending();
      async.elapse(const Duration(milliseconds: 40));
      expect(out, isEmpty);
    });
  });

  test('add() after dispose is a no-op and never throws', () {
    withThrottle((async, throttle, out) {
      throttle.dispose();
      async.flushMicrotasks();
      throttle.add(activity(SyncActivityKind.paused, 5));
      throttle.add(activity(SyncActivityKind.seekedForward, 5));
      async.elapse(const Duration(milliseconds: 40));
      expect(out, isEmpty);
    });
  });
}
