import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/connection_watchdog.dart';

/// The watchdog exists to catch a *silently* dead connection — a half-open TCP
/// where the server stops sending without a clean close, so socket
/// onDone/onError never fire. It watches the gap between incoming bytes and
/// trips [onTimeout] once that gap exceeds [timeout].
void main() {
  group('ConnectionWatchdog', () {
    test('fires onTimeout when no bump arrives within the timeout', () {
      fakeAsync((async) {
        var fired = 0;
        ConnectionWatchdog(
          timeout: const Duration(seconds: 12),
          onTimeout: () => fired++,
        ).bump();

        async.elapse(const Duration(seconds: 11));
        expect(fired, 0, reason: 'still within the window');
        async.elapse(const Duration(seconds: 2));
        expect(fired, 1, reason: 'window elapsed with no bump');
      });
    });

    test('each bump resets the countdown (steady heartbeat never trips)', () {
      fakeAsync((async) {
        var fired = 0;
        final dog = ConnectionWatchdog(
          timeout: const Duration(seconds: 12),
          onTimeout: () => fired++,
        );
        // A heartbeat every second for a long stretch must never trip.
        for (var i = 0; i < 100; i++) {
          dog.bump();
          async.elapse(const Duration(seconds: 1));
        }
        expect(fired, 0);
        // Now go silent — it trips once.
        async.elapse(const Duration(seconds: 12));
        expect(fired, 1);
      });
    });

    test('stop() cancels a pending timeout', () {
      fakeAsync((async) {
        var fired = 0;
        final dog = ConnectionWatchdog(
          timeout: const Duration(seconds: 12),
          onTimeout: () => fired++,
        )..bump();
        async.elapse(const Duration(seconds: 5));
        dog.stop();
        async.elapse(const Duration(seconds: 60));
        expect(fired, 0);
        expect(dog.isRunning, isFalse);
      });
    });

    test('fires only once per silent gap (no repeat without re-bump)', () {
      fakeAsync((async) {
        var fired = 0;
        ConnectionWatchdog(
          timeout: const Duration(seconds: 12),
          onTimeout: () => fired++,
        ).bump();
        async.elapse(const Duration(seconds: 60));
        expect(fired, 1);
      });
    });
  });

  group('reconnectBackoff', () {
    test('doubles each attempt from the base', () {
      expect(reconnectBackoff(attempt: 0), const Duration(seconds: 1));
      expect(reconnectBackoff(attempt: 1), const Duration(seconds: 2));
      expect(reconnectBackoff(attempt: 2), const Duration(seconds: 4));
      expect(reconnectBackoff(attempt: 3), const Duration(seconds: 8));
    });

    test('caps at the max delay', () {
      expect(reconnectBackoff(attempt: 20), const Duration(seconds: 30));
      expect(reconnectBackoff(attempt: 999), const Duration(seconds: 30));
    });

    test('clamps a negative attempt to the base', () {
      expect(reconnectBackoff(attempt: -5), const Duration(seconds: 1));
    });
  });
}
