import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/ping_service.dart';

void main() {
  group('PingService', () {
    test('first RTT sample is adopted directly', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('with window 1 the EMA matches upstream exactly', () {
      final ping = PingService(weight: 0.85, window: 1);
      ping.recordRtt(0.10);
      ping.recordRtt(0.20);
      // 0.85*0.10 + 0.15*0.20 = 0.115
      expect(ping.rtt, closeTo(0.115, 1e-9));
    });

    test('forwardDelay is half the RTT', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.forwardDelay, closeTo(0.05, 1e-9));
    });

    test('a single spike is rejected by the median, not averaged in', () {
      final ping = PingService(weight: 0.85, window: 5);
      for (var i = 0; i < 5; i++) {
        ping.recordRtt(0.10);
      }
      expect(ping.rtt, closeTo(0.10, 1e-9));
      // One 5s flap is 1 of 5 → never the middle element, so the EMA never sees
      // it. A plain mean would jump to 0.835 here.
      ping.recordRtt(5.0);
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('recurring spikes are rejected while a minority of the window', () {
      final ping = PingService(weight: 0.85, window: 5);
      for (var i = 0; i < 5; i++) {
        ping.recordRtt(0.10);
      }
      // 1-in-3 spikes: at most 2 fall in any 5-sample window, so the median
      // stays 0.10 and the estimate never ratchets up (the repeated-outlier
      // case a clamp mishandles).
      for (var i = 0; i < 10; i++) {
        ping.recordRtt(5.0);
        ping.recordRtt(0.10);
        ping.recordRtt(0.10);
      }
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('a sustained shift converges once it dominates the window', () {
      final ping = PingService(weight: 0.85, window: 5);
      for (var i = 0; i < 5; i++) {
        ping.recordRtt(0.10);
      }
      // Two samples at the new level are still a minority (2 of 5) → median
      // unmoved: the median's built-in ~window/2 tracking lag.
      ping.recordRtt(5.0);
      ping.recordRtt(5.0);
      expect(ping.rtt, closeTo(0.10, 1e-9));
      // The third makes the new level the majority → median flips, EMA climbs.
      ping.recordRtt(5.0);
      expect(ping.rtt, greaterThan(0.10));
      for (var i = 0; i < 40; i++) {
        ping.recordRtt(5.0);
      }
      expect(ping.rtt, closeTo(5.0, 0.05));
    });

    test('window must be odd', () {
      expect(() => PingService(window: 4), throwsA(isA<AssertionError>()));
    });

    test(
      'warm-up: a spike before the window fills never enters the estimate',
      () {
        final ping = PingService(weight: 0.85, window: 5);
        ping.recordRtt(0.10);
        // Spike as the 2nd sample. An upper-middle partial median would pick the
        // 5s flap here and feed it to the EMA (0.835s); the warm-up policy —
        // running lower-middle median, no EMA until the window is full — keeps
        // the estimate on the good sample.
        ping.recordRtt(5.0);
        expect(ping.rtt, closeTo(0.10, 1e-9));
        ping.recordRtt(0.10);
        ping.recordRtt(0.10);
        expect(ping.rtt, closeTo(0.10, 1e-9));
        // Window full — EMA takes over from a clean seed.
        ping.recordRtt(0.10);
        expect(ping.rtt, closeTo(0.10, 1e-9));
      },
    );

    test('warm-up: a spiky first sample is forgotten, not decayed through', () {
      final ping = PingService(weight: 0.85, window: 5);
      ping.recordRtt(5.0);
      // One sample: nothing else to trust yet.
      expect(ping.rtt, closeTo(5.0, 1e-9));
      // As soon as a normal sample lands, the running median drops the spike
      // outright — no EMA memory of it to decay through over many heartbeats.
      ping.recordRtt(0.10);
      expect(ping.rtt, closeTo(0.10, 1e-9));
      ping.recordRtt(0.10);
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('warm-up: genuine samples track the running median', () {
      final ping = PingService(weight: 0.85, window: 5);
      ping.recordRtt(0.10);
      ping.recordRtt(0.20);
      ping.recordRtt(0.30);
      expect(ping.rtt, closeTo(0.20, 1e-9));
    });

    test('newTimestamp returns a monotonically sensible epoch seconds', () {
      final ping = PingService();
      final a = ping.newTimestamp();
      expect(a, greaterThan(0));
    });
  });

  group('rttSampleFromEcho', () {
    test('returns round-trip seconds from an echoed timestamp', () {
      final sample = rttSampleFromEcho(
        echoedTimestamp: 100.0,
        nowEpochSeconds: 100.25,
      );
      expect(sample, closeTo(0.25, 1e-9));
    });

    test('returns null when there is no echo', () {
      expect(
        rttSampleFromEcho(echoedTimestamp: null, nowEpochSeconds: 100.0),
        isNull,
      );
    });

    test('returns null on a negative result (clock skew / stale echo)', () {
      expect(
        rttSampleFromEcho(echoedTimestamp: 100.0, nowEpochSeconds: 99.5),
        isNull,
      );
    });
  });
}
