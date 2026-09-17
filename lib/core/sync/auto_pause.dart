import 'package:meta/meta.dart';

/// Whether the co-watch session is currently in sync: connected to the room
/// AND at least one friend is present. Either condition failing means you'd be
/// watching alone, out of sync.
@immutable
class SyncHealth {
  const SyncHealth({required this.connected, required this.hasPeer});

  final bool connected;
  final bool hasPeer;

  bool get healthy => connected && hasPeer;
}

/// Should the local video auto-pause right now?
///
/// Fires only on the *edge* from healthy to unhealthy while the video is
/// playing — so a deliberate play while already alone is respected and never
/// re-paused. On restore (unhealthy -> healthy) it does nothing: the video
/// stays paused until the watchers hit play together.
bool decideAutoPause({
  required bool wasHealthy,
  required bool nowHealthy,
  required bool isPlaying,
}) {
  return wasHealthy && !nowHealthy && isPlaying;
}

/// Why sync dropped — decides how the auto-pause banner/chat line is phrased.
enum AutoPauseCause { peerLeft, connectionLost }

/// Classify why sync became unhealthy so the message tells the truth.
///
/// A friend leaving means we're *still connected* but the room is now empty;
/// only then do we name them. Any other drop (socket disconnect, server error)
/// is a connection loss — even if a stale "peer present" flag lingers — and
/// must never claim someone left.
AutoPauseCause autoPauseCause({
  required bool connected,
  required bool hasPeer,
}) {
  return connected && !hasPeer
      ? AutoPauseCause.peerLeft
      : AutoPauseCause.connectionLost;
}

/// Banner/chat text for an auto-pause. [peerName] is the friend who left and is
/// used only for [AutoPauseCause.peerLeft] (falling back to "Friend" when the
/// name is unknown); a connection loss ignores it and stays generic.
String autoPauseMessage({required AutoPauseCause cause, String? peerName}) {
  switch (cause) {
    case AutoPauseCause.peerLeft:
      return '${peerName ?? 'Friend'} left, auto-paused';
    case AutoPauseCause.connectionLost:
      return 'Paused — lost sync with your friend';
  }
}
