import 'dart:async';

import 'peer_state.dart';

/// Collapses a flood of consecutive seek notifications into a single final one
/// (issue #26). Holding the seek keys or dragging the scrubber fires a rapid
/// stream of seek [SyncActivity]s; without this every step would spam its own
/// "skipped to …" chat line and banner flash.
///
/// Seeks are trailing-debounced: each new seek resets a [window] timer, and only
/// the most recent (the landing position) is emitted once scrubbing settles.
/// Play/pause events pass straight through — they are deliberate single actions,
/// never a flood — and a non-seek event flushes any pending seek ahead of itself
/// so chronological order is preserved.
///
/// Drift corrections ([SyncActivityKind.driftRewound], #98) are rate-limited
/// rather than debounced: the first one passes through immediately, then any
/// further correction inside [driftCooldown] is dropped so a rough patch of
/// repeated rewinds cannot spam chat with a stack of identical notices.
class SyncActivityThrottle {
  SyncActivityThrottle({
    this.window = const Duration(milliseconds: 800),
    this.driftCooldown = const Duration(seconds: 8),
  });

  /// Quiet period after the last seek before the collapsed notification fires.
  final Duration window;

  /// Minimum gap between two emitted drift-correction notices.
  final Duration driftCooldown;

  final StreamController<SyncActivity> _out =
      StreamController<SyncActivity>.broadcast();

  Timer? _seekTimer;
  SyncActivity? _pendingSeek;
  Timer? _driftCooldownTimer;
  bool _disposed = false;

  /// Throttled output — wire the UI (banner + chat) to this, not to the raw
  /// activity stream.
  Stream<SyncActivity> get stream => _out.stream;

  void add(SyncActivity activity) {
    if (_disposed) return;
    if (activity.kind == SyncActivityKind.driftRewound) {
      if (_driftCooldownTimer != null) return; // still cooling down — drop it.
      _flushSeek();
      _out.add(activity);
      _driftCooldownTimer = Timer(driftCooldown, () {
        _driftCooldownTimer = null;
      });
      return;
    }
    final isSeek =
        activity.kind == SyncActivityKind.seekedForward ||
        activity.kind == SyncActivityKind.seekedBack;
    if (!isSeek) {
      _flushSeek();
      _out.add(activity);
      return;
    }
    _pendingSeek = activity;
    _seekTimer?.cancel();
    _seekTimer = Timer(window, _flushSeek);
  }

  void _flushSeek() {
    _seekTimer?.cancel();
    _seekTimer = null;
    final pending = _pendingSeek;
    _pendingSeek = null;
    if (pending != null && !_disposed) _out.add(pending);
  }

  /// Drop queued seek / drift notices without closing the stream. Used when
  /// the session leaves Syncplay so a pending timer cannot fire later.
  void clearPending() {
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingSeek = null;
    _driftCooldownTimer?.cancel();
    _driftCooldownTimer = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    clearPending();
    await _out.close();
  }
}
