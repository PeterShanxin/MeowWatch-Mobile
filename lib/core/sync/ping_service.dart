/// Tracks RTT as an exponential moving average and derives the one-way forward
/// delay used to latency-compensate a peer's reported position. Mirrors
/// upstream's PingService (PING_MOVING_AVERAGE_WEIGHT = 0.85).
class PingService {
  PingService({this.weight = 0.85, this.window = 5})
    : assert(window >= 1 && window.isOdd, 'window must be odd and >= 1');

  final double weight;

  /// Size of the running window whose median feeds the EMA. A median rejects a
  /// minority of outliers by construction — up to `window ~/ 2` of the last
  /// [window] samples can be spikes and none reaches the average. This is what
  /// keeps a VPN latency flap (rekey, route change) from swinging [forwardDelay]
  /// — and thus the drift-rewind decision in `decideFollow` — off a single bad
  /// heartbeat, without the ratchet-up a plain clamp suffers when the same spike
  /// recurs. Kept **odd** so the median is one element, never the average of two
  /// middles (which could itself be pulled toward an outlier). A genuine shift is
  /// still tracked: once it dominates the window the median flips, ~[window] ~/ 2
  /// samples behind, then the EMA converges as before.
  ///
  /// While the buffer is still filling (warm-up) the estimate is the running
  /// median itself — no EMA — so a spike among the first few samples is
  /// dropped the moment good samples outnumber it instead of lingering in the
  /// average (see [recordRtt]).
  final int window;

  final List<double> _recent = <double>[];
  double _rtt = 0.0;
  bool _hasSample = false;

  double get rtt => _rtt;

  /// One-way delay estimate (half the round trip).
  double get forwardDelay => _rtt / 2.0;

  void recordRtt(double sample) {
    _recent.add(sample);
    if (_recent.length > window) _recent.removeAt(0);
    // Median of the current window (the buffer is short — a sort is trivial).
    // With an odd full window `(length - 1) ~/ 2` is the exact middle; during
    // warm-up an even-length buffer takes the LOWER middle, so a spike needs a
    // strict majority of the partial buffer — not just half — to reach the
    // estimate. Biasing low is the safe direction: a briefly understated RTT
    // means a touch less latency compensation, while an overstated one is what
    // trips the drift-rewind.
    final median = (<double>[..._recent]..sort())[(_recent.length - 1) ~/ 2];
    if (!_hasSample || _recent.length < window) {
      // Warm-up: the estimate IS the running median. Blending medians into an
      // EMA before the window fills would let a startup spike linger for many
      // heartbeats; the running median instead forgets it outright as soon as
      // good samples outnumber it. Once the window is full the EMA takes over
      // from a spike-free seed. (`_hasSample` matters only for window == 1,
      // where the buffer is "full" from the very first sample.)
      _rtt = median;
      _hasSample = true;
    } else {
      _rtt = weight * _rtt + (1 - weight) * median;
    }
  }

  /// Epoch seconds as a double, sent as clientLatencyCalculation so the peer's
  /// echo lets us measure RTT on the next State.
  double newTimestamp() => DateTime.now().millisecondsSinceEpoch / 1000.0;
}

/// Round-trip time sample (seconds) derived from the server echoing back the
/// clientLatencyCalculation timestamp we previously sent: the round trip is
/// simply `now - echoed`. Returns null when there is no echo, or when the
/// result is negative (clock skew or a stale echo), mirroring upstream
/// Syncplay's guard so a bad sample never pollutes the moving average.
double? rttSampleFromEcho({
  required double? echoedTimestamp,
  required double nowEpochSeconds,
}) {
  if (echoedTimestamp == null) return null;
  final rtt = nowEpochSeconds - echoedTimestamp;
  if (rtt < 0) return null;
  return rtt;
}
