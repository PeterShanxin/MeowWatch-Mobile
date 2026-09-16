import 'package:meta/meta.dart';

import 'peer_state.dart';
import 'syncplay_constants.dart';

/// What the local player should do in response to a relayed global room state.
@immutable
class FollowAction {
  const FollowAction.none()
    : shouldApply = false,
      position = Duration.zero,
      paused = true;

  const FollowAction.apply({required this.position, required this.paused})
    : shouldApply = true;

  final bool shouldApply;
  final Duration position;
  final bool paused;
}

/// Decide whether to follow the room's [global] playstate, mirroring upstream
/// Syncplay's `_changePlayerStateAccordingToGlobalState`. The two rules that
/// stop clients fighting:
///   1. A play/pause flip is detected by comparing the global paused flag to
///      our own local paused flag — so once we match, steady heartbeats do
///      nothing, and our own change (already reflected locally) never echoes.
///   2. Seeks and drift-rewinds are ignored when the change was [setBy] us.
/// Position is only corrected on an explicit peer seek, or when our player has
/// run AHEAD of the room by more than [rewindThreshold] (one-directional).
FollowAction decideFollow({
  required PeerPlayState global,
  required bool localPaused,
  required Duration localPosition,
  required String username,
  bool peerStalled = false,
  Duration rewindThreshold = SyncplayConstants.rewindThreshold,
}) {
  final isSelf = global.setBy != null && global.setBy == username;

  // Never follow a state we ourselves set. During the brief window after we
  // change play/pause but before the server acknowledges, the server keeps
  // echoing the OLD global state stamped with our name; applying it would undo
  // our own change and start the ping-pong fight.
  if (isSelf) return const FollowAction.none();

  // A global state with no [setBy] is the server's empty-room default
  // (position 0, paused) — seen when the room momentarily empties on a
  // reconnect blip. It is not a real user's action, so following it (even via
  // the pause/play-flip rule below) would pause us and yank a mid-film session
  // back to 00:00. Ignore any setter-less state; only a named peer can move us.
  if (global.setBy == null) return const FollowAction.none();

  // 1. Pause/play flip — compare to local, so once we match, steady
  //    heartbeats produce no action.
  if (global.paused != localPaused) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 2. Explicit seek by someone else.
  if (global.doSeek && !isSelf) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 3. Rewind only if WE are ahead of the room beyond the threshold. The
  //    empty-room phantom-zero case (position 0, no setter, seen when both
  //    clients drop and rejoin together) would otherwise make each client "far
  //    ahead" of that phantom 0 and rewind to it, dragging a mid-film session
  //    back to 00:00 — but the setter-less early return above already filters
  //    it out, so no extra guard is needed here.
  //
  //    [peerStalled] suppresses this rewind: a peer that claims `playing` while
  //    frozen (its position not advancing) would otherwise pull us into an
  //    endless rewind sawtooth — we run ahead of the stuck frame, rewind to it,
  //    replay, run ahead, rewind again (the 2026-06-20 field regression). Don't
  //    chase a peer who isn't moving; keep playing and let them catch up. The
  //    pause-flip and explicit-seek rules above still fire, so a genuine pause
  //    or seek by that peer is still followed.
  final aheadBy = localPosition - global.position;
  if (!global.doSeek && !peerStalled && aheadBy > rewindThreshold) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  return const FollowAction.none();
}
