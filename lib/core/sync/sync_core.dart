import 'dart:async';

import 'package:meta/meta.dart';

import 'peer_state.dart';

/// Abstract interface for room sync. Implementations may speak the Syncplay
/// protocol over a socket, or be a fake for tests. Commands in, streams out —
/// the same shape as VideoCore.
abstract class SyncCore {
  final StreamController<SyncConnectionState> _connection =
      StreamController<SyncConnectionState>.broadcast();
  // Peer state is the command path from the room to the local player. Deliver it
  // before the Syncplay heartbeat reply continues so cache and video stay paired.
  final StreamController<PeerPlayState> _peer =
      StreamController<PeerPlayState>.broadcast(sync: true);
  final StreamController<PeerPlayState> _observedRoom =
      StreamController<PeerPlayState>.broadcast(sync: true);
  final StreamController<PresenceEvent> _presence =
      StreamController<PresenceEvent>.broadcast();
  final StreamController<ChatMessage> _chat =
      StreamController<ChatMessage>.broadcast();
  final StreamController<PeerFile> _peerFile =
      StreamController<PeerFile>.broadcast();
  final StreamController<SyncActivity> _activity =
      StreamController<SyncActivity>.broadcast();

  /// Fires once — on the first roster reply after login — with the names of
  /// members already in the room when the local user arrived. Empty list means
  /// the room was empty. Does NOT fire again on reconnect.
  final StreamController<List<String>> _initialRoster =
      StreamController<List<String>>.broadcast();

  bool _disposed = false;
  SyncConnectionState? _lastConnectionState;
  PeerPlayState? _lastObservedRoomState;
  Stopwatch? _roomStateClock;
  PeerPlayState? _lastAdvancingRoomState;
  Stopwatch? _advancingRoomClock;

  Stream<SyncConnectionState> get connectionState => _connection.stream;

  /// Last emitted connection state. Broadcast listeners miss events that fire
  /// with nobody attached; the lobby and watch route use this so a terminal
  /// Error during the join handoff is not dropped (#265).
  SyncConnectionState? get lastConnectionState => _lastConnectionState;

  Stream<PeerPlayState> get peerState => _peer.stream;

  /// Every named room heartbeat, including states that need no follow action.
  /// Recovery uses a fresh paused observation to distinguish a later Play from
  /// an unpaused state left over from before the connection was lost.
  Stream<PeerPlayState> get observedRoomState => _observedRoom.stream;
  Stream<PresenceEvent> get presence => _presence.stream;
  Stream<ChatMessage> get chat => _chat.stream;

  /// Last room playstate observed from the server, including heartbeats that
  /// [decideFollow] did not apply. Joiners need this: syncplay.pl's first State
  /// to a new watcher has `doSeek=false`, so nothing is emitted on [peerState]
  /// until a later pause or seek, and [PlaybackSyncBridge.markSourceOpen] must
  /// still land the room.
  PeerPlayState? get lastObservedRoomState => _lastObservedRoomState;
  set lastObservedRoomState(PeerPlayState? state) {
    _lastObservedRoomState = state;
    _roomStateClock = state == null ? null : (Stopwatch()..start());
    if (!_disposed && state != null) _observedRoom.add(state);
  }

  /// Monotonic age of the actual received heartbeat, including unapplied ones.
  Duration? get lastObservedRoomStateAge => _roomStateClock?.elapsed;

  /// A heartbeat that passed the concrete client's self/handshake/stall and
  /// forward-progress checks. Only the optional local rate correction uses it.
  PeerPlayState? get lastAdvancingRoomState => _lastAdvancingRoomState;
  Duration? get lastAdvancingRoomStateAge => _advancingRoomClock?.elapsed;
  set lastAdvancingRoomState(PeerPlayState? state) {
    _lastAdvancingRoomState = state;
    _advancingRoomClock = state == null ? null : (Stopwatch()..start());
  }

  /// Files announced by peers (on join, on the roster, and on mid-session file
  /// changes). Drives the file-mismatch warning.
  Stream<PeerFile> get peerFile => _peerFile.stream;

  /// Deliberate peer playback actions (play/pause/seek) to announce.
  Stream<SyncActivity> get activity => _activity.stream;

  /// Fires once with the roster members present on first join.
  Stream<List<String>> get initialRoster => _initialRoster.stream;

  @protected
  void emitConnectionState(SyncConnectionState s) {
    _lastConnectionState = s;
    if (!_disposed) _connection.add(s);
  }

  @protected
  void emitPeerState(PeerPlayState s) {
    if (!_disposed) _peer.add(s);
  }

  @protected
  void emitPresence(PresenceEvent e) {
    if (!_disposed) _presence.add(e);
  }

  @protected
  void emitChat(ChatMessage m) {
    if (!_disposed) _chat.add(m);
  }

  @protected
  void emitPeerFile(PeerFile f) {
    if (!_disposed) _peerFile.add(f);
  }

  @protected
  void emitActivity(SyncActivity a) {
    if (!_disposed) _activity.add(a);
  }

  @protected
  void emitInitialRoster(List<String> members) {
    if (!_disposed) _initialRoster.add(members);
  }

  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  });

  Future<void> disconnect();

  /// Announce the locally loaded file to the room.
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  });

  /// Push the latest local playback position/paused state. Called frequently
  /// (every position tick); the implementation stores it for the next State
  /// heartbeat — it does not necessarily transmit immediately.
  void updateLocalState({required Duration position, required bool paused});

  /// Mark that the local user just changed state (play/pause/seek) so the next
  /// State carries the ignoringOnTheFly handshake. [doSeek] true for seeks.
  void notifyLocalChange({required bool doSeek});

  void sendChat(String text);

  @protected
  Future<void> disposeBackend();

  @mustCallSuper
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disposeBackend();
    await _connection.close();
    await _peer.close();
    await _observedRoom.close();
    await _presence.close();
    await _chat.close();
    await _peerFile.close();
    await _activity.close();
    await _initialRoster.close();
  }
}
