import 'peer_state.dart';

/// Chat line announced when the local link drops from a live connection.
const String connectionLostMessage = 'Connection lost — reconnecting…';

/// Chat line announced when the local link returns after a reconnect.
const String reconnectedToRoomMessage = 'Reconnected to room.';

/// Build the chat system line shown when a peer deliberately leaves vs drops.
String peerDepartureMessage({required String username, required bool clean}) =>
    clean ? '$username left the room.' : '$username lost connection.';

/// Build the chat system line shown when a peer joins for the first time or
/// rejoins after a detected drop.
String peerJoinMessage({required String username, required bool reconnected}) =>
    reconnected ? '$username reconnected.' : '$username joined the room.';

/// True when the link just dropped from a live connection — the moment to
/// announce a connection loss. Gated to the `connected → reconnecting` edge so
/// the repeated backoff attempts (`handshaking → reconnecting`) don't
/// re-announce on every retry.
bool isConnectionDrop({
  required SyncConnectionStatus prev,
  required SyncConnectionStatus next,
}) =>
    next == SyncConnectionStatus.reconnecting &&
    prev == SyncConnectionStatus.connected;

/// True when we've arrived back at [SyncConnectionStatus.connected] while a
/// reconnect was underway. [wasReconnecting] is a latch the caller sets on a
/// drop and clears here — needed because the reconnect path passes through an
/// intermediate `handshaking` state, so a simple `prev` comparison can't see
/// that a reconnect was in progress. A first connect never sets the latch, so
/// the initial login stays silent.
bool isReconnectSuccess({
  required bool wasReconnecting,
  required SyncConnectionStatus next,
}) => wasReconnecting && next == SyncConnectionStatus.connected;

/// True when this room session never completed a login and the client has
/// stopped trying. The start screen should show the named error; the watch
/// UI is only for a completed join (#264, #265).
///
/// A public-candidate walk that is still looking is not a failed join —
/// a dead first port is "try the next one", not "return to the lobby".
bool isFailedInitialJoin({
  required SyncConnectionStatus status,
  required bool everConnected,
  bool lookingForServer = false,
}) =>
    !everConnected && !lookingForServer && status == SyncConnectionStatus.error;

/// The name of our own lingering ghost session to silence on its imminent
/// departure, or null if there is none.
///
/// The ghost is simply **the name we held before the drop** when the server
/// won't hand it back on [reconnected] login: we requested it again, but
/// [assignedName] came back different ("meowPEOW" → "meowPEOW_") because our own
/// just-dropped session is still occupying [previousAssignedName] and is about
/// to be reaped. Its `left` event would otherwise surface as a peer "lost
/// connection." — but the name was ours moments ago, which confused users (#93
/// field report).
///
/// Keying on [previousAssignedName] (not the chosen name) is what keeps this
/// safe — and is the answer to the #93 reconnect-window ambiguity. A bare suffix
/// is not enough: a *real namesake* who owns the chosen name also forces a
/// suffix, but in that case the server hands us back the **same** suffixed name
/// we already carried ([assignedName] == [previousAssignedName]), so we return
/// null and the namesake's departure still shows. We only ever name our own
/// prior identity, never a peer's. It also handles compounding suffixes: if we
/// were "meowPEOW_" and reconnect as "meowPEOW", the orphaned "meowPEOW_" is the
/// ghost. (The one residual — a real peer grabs our exact freed name during the
/// blip — is bounded at the call site by a recency window.)
///
/// This only silences the one departure line; it never hides a peer's presence
/// or file.
String? ownGhostNameOnReconnect({
  required bool reconnected,
  required String? previousAssignedName,
  required String? assignedName,
}) =>
    (reconnected &&
        assignedName != null &&
        previousAssignedName != null &&
        assignedName != previousAssignedName)
    ? previousAssignedName
    : null;

/// True when [departedAt] is non-null and falls within [window] of [now],
/// meaning a peer's departure is recent enough to be treated as a reconnect
/// rather than a fresh join.
bool isPeerReconnect({
  DateTime? departedAt,
  required DateTime now,
  Duration window = const Duration(seconds: 60),
}) => departedAt != null && now.difference(departedAt) <= window;
