/// Detects a peer whose player claims to be *playing* while its position is not
/// actually advancing — a frozen/stuck engine.
///
/// This guards the rewind amplifier: in a two-person room the room's "global"
/// position is just the other user's reported position. If that user's engine
/// freezes mid-resume it keeps broadcasting `playing` at a stuck frame, so our
/// (correctly advancing) side runs ahead, the drift-rewind rule yanks us back to
/// the stuck frame, we replay, run ahead again, rewind again — an unwatchable
/// sawtooth (the 2026-06-20 field regression). When this flags a stall,
/// [decideFollow] stands its drift-rewind down so we keep playing smoothly
/// instead of chasing a peer who isn't moving.
///
/// Detection is heartbeat-count based (no clock): the Syncplay State heartbeat
/// arrives roughly once per second, so a handful of consecutive `playing`
/// heartbeats with no net advance past the baseline is a freeze. Comparing to a
/// fixed baseline (not the previous tick) makes it robust to the small position
/// wobble a frozen mpv reports around the stuck frame.
class PeerStallTracker {
  PeerStallTracker({
    this.stallTicks = 4,
    this.advanceEpsilon = const Duration(seconds: 2),
  });

  /// Consecutive non-advancing `playing` heartbeats before a stall is declared.
  /// At ~1 heartbeat/second this is roughly the stall's wall-clock duration.
  final int stallTicks;

  /// Minimum net advance past the baseline that counts as genuine playback (and
  /// re-baselines). Set above the frozen-engine position wobble so noise around
  /// a stuck frame is never mistaken for progress.
  final Duration advanceEpsilon;

  Duration? _baseline;
  int _ticks = 0;
  bool _stalled = false;

  /// True once the peer has claimed `playing` without advancing for
  /// [stallTicks] heartbeats. Cleared as soon as it advances, pauses, or seeks.
  bool get stalled => _stalled;

  /// Feed one peer heartbeat. [position] is the peer's raw reported position;
  /// [paused]/[doSeek] come from the same state.
  void update({
    required Duration position,
    required bool paused,
    required bool doSeek,
  }) {
    // A paused peer is not frozen, and an explicit seek is an intentional
    // reposition — both reset the baseline so post-event ticks start fresh.
    if (paused || doSeek) {
      _reset(position);
      return;
    }
    final baseline = _baseline;
    if (baseline == null) {
      // First playing heartbeat just seeds the baseline.
      _baseline = position;
      _ticks = 0;
      return;
    }
    if ((position - baseline).abs() > advanceEpsilon) {
      // A meaningful MOVE off the baseline — forward progress (the peer is
      // playing) or a backward jump (a reload/seek-back that skipped doSeek).
      // Either way it is not a frozen frame, so re-baseline here.
      _reset(position);
      return;
    }
    _ticks++;
    if (_ticks >= stallTicks) _stalled = true;
  }

  void _reset(Duration position) {
    _baseline = position;
    _ticks = 0;
    _stalled = false;
  }
}
