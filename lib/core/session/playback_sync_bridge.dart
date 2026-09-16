import 'dart:async';

import '../media/media_item.dart';
import '../playback/playback_target.dart';
import '../sync/peer_state.dart';
import '../sync/sync_core.dart';

/// Mobile adaptation of desktop MeowWatch's source-confirmed sync boundary.
/// Player events feed heartbeats; only explicit user commands signal a change.
/// This prevents delayed native seek/play events from echoing peer commands.
class PlaybackSyncBridge {
  PlaybackSyncBridge({
    required this.target,
    required this.sync,
    required this.authorizePlayback,
    this.onError,
    this.commandTimeout = const Duration(seconds: 5),
    this.settleWindow = const Duration(seconds: 3),
  });

  final PlaybackTarget target;
  final SyncCore sync;
  final Future<bool> Function() authorizePlayback;
  final void Function(Object error)? onError;
  final Duration commandTimeout;
  final Duration settleWindow;
  StreamSubscription<PlaybackSnapshot>? _playerSub;
  StreamSubscription<PeerPlayState>? _peerSub;
  StreamSubscription<SyncConnectionState>? _connectionSub;
  Future<void> _tail = Future<void>.value();
  String? _confirmed;
  int _sourceGeneration = 0;
  int _intent = 0;
  Completer<void> _superseded = Completer<void>();
  int _applying = 0;
  bool _disposed = false;
  bool _connected = false;
  PeerPlayState? _latestPeer;
  PeerPlayState? _expected;
  DateTime _expectedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (_disposed || _playerSub != null) return;
    _connected =
        sync.lastConnectionState?.status == SyncConnectionStatus.connected;
    _playerSub = target.states.listen(_onPlayer);
    _peerSub = sync.peerState.listen(_onPeer);
    _connectionSub = sync.connectionState.listen((state) {
      final connected = state.status == SyncConnectionStatus.connected;
      final lost = _connected && !connected;
      _connected = connected;
      if (lost) _background(peerLeft());
      if (connected && _hasSource) {
        final snapshot = target.snapshot;
        sync.announceFile(
          name: snapshot.media!.title,
          size: snapshot.media!.sizeBytes ?? 0,
          duration: snapshot.duration,
        );
      }
    });
  }

  bool get _hasSource =>
      !_disposed &&
      target.snapshot.ready &&
      _confirmed != null &&
      target.snapshot.media?.uri.toString() == _confirmed;

  /// Invalidate a previous load or remote command before starting a new source.
  /// Pass this generation to [markSourceOpen] after accepting the load.
  int beginSourceLoad() {
    _confirmed = null;
    _expected = null;
    _nextIntent();
    return ++_sourceGeneration;
  }

  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    if (_disposed) return;
    final generation = beginSourceLoad();
    await target.load(media, position: position);
    await markSourceOpen(media.uri.toString(), generation: generation);
  }

  Future<void> markSourceOpen(String source, {int? generation}) async {
    if (_disposed ||
        (generation != null && generation != _sourceGeneration) ||
        !target.snapshot.ready ||
        target.snapshot.media?.uri.toString() != source) {
      return;
    }
    _confirmed = source;
    final snapshot = target.snapshot;
    sync.announceFile(
      name: snapshot.media!.title,
      size: snapshot.media!.sizeBytes ?? 0,
      duration: snapshot.duration,
    );
    // Room time can advance while a native load is pending; use the latest
    // observed heartbeat, even when follow logic did not emit an action.
    final peer = sync.lastObservedRoomState ?? _latestPeer;
    if (peer != null && peer.setBy != null) {
      _onPeer(
        PeerPlayState(
          position: peer.position,
          paused: peer.paused,
          doSeek: true,
          setBy: peer.setBy,
        ),
      );
      await _tail;
    } else {
      _publish(snapshot, changed: false);
    }
  }

  /// Local -> Together adopts an already accepted source. An explicit seek
  /// assertion seeds the room; a heartbeat alone cannot move Syncplay's state.
  Future<void> adoptOpenSource(String source) async {
    if (_disposed ||
        !target.snapshot.ready ||
        target.snapshot.media?.uri.toString() != source) {
      return;
    }
    _confirmed = source;
    if (sync.lastObservedRoomState?.setBy != null) {
      await markSourceOpen(source);
      return;
    }
    final snapshot = target.snapshot;
    sync.announceFile(
      name: snapshot.media!.title,
      size: snapshot.media!.sizeBytes ?? 0,
      duration: snapshot.duration,
    );
    if (snapshot.playing) {
      // Moving a running Local session into Together must pass the same host
      // allowance check as pressing Play in a newly created Together room.
      await target.pause();
      if (await play()) return;
    }
    _publish(target.snapshot, changed: true, seek: true);
  }

  void _onPlayer(PlaybackSnapshot state) {
    if (!_hasSource || _applying != 0) return;
    final expected = _expected;
    if (expected != null &&
        DateTime.now().difference(_expectedAt) < settleWindow) {
      final elapsed = DateTime.now().difference(_expectedAt);
      final drift = state.position - expected.position;
      final matches =
          state.playing == !expected.paused &&
          drift >= -const Duration(milliseconds: 500) &&
          drift <=
              (expected.paused ? Duration.zero : elapsed) +
                  const Duration(milliseconds: 500);
      if (!matches) return;
    }
    _publish(state, changed: false);
  }

  void _publish(
    PlaybackSnapshot state, {
    required bool changed,
    bool seek = false,
  }) {
    if (!_hasSource) return;
    sync.updateLocalState(position: state.position, paused: !state.playing);
    if (changed) sync.notifyLocalChange(doSeek: seek);
  }

  void _acknowledge(PeerPlayState state) {
    _expected = state;
    _expectedAt = DateTime.now();
    // Synchronous acknowledgement is required before Syncplay replies to the
    // current State. Native player commands may complete much later.
    sync.updateLocalState(position: state.position, paused: state.paused);
  }

  void _onPeer(PeerPlayState peer) {
    if (_disposed) return;
    _latestPeer = peer;
    _acknowledge(peer);
    if (!_hasSource) return;
    final intent = _nextIntent();
    final source = _sourceGeneration;
    _background(
      _enqueue(() async {
        if (!_current(intent, source)) return;
        _applying++;
        try {
          if (!peer.paused && !await _authorize()) {
            if (_current(intent, source)) await _denyPlayback();
            return;
          }
          if (!_current(intent, source)) return;
          await target.pause().timeout(commandTimeout);
          if (!_current(intent, source)) return;
          await target.seek(peer.position).timeout(commandTimeout);
          if (!_current(intent, source)) return;
          if (!peer.paused) await target.play().timeout(commandTimeout);
          if (_current(intent, source)) _acknowledge(peer);
        } catch (_) {
          if (_current(intent, source)) {
            try {
              await target.pause().timeout(commandTimeout);
            } catch (_) {
              // Preserve the original native-command error for the caller.
            }
            _expected = null;
            _publish(target.snapshot, changed: true);
          }
          rethrow;
        } finally {
          _applying--;
        }
      }),
    );
  }

  bool _current(int intent, int source) =>
      _hasSource && intent == _intent && source == _sourceGeneration;

  int _nextIntent() {
    _superseded.complete();
    _superseded = Completer<void>();
    return ++_intent;
  }

  Future<bool> _authorize() =>
      Future.any([authorizePlayback(), _superseded.future.then((_) => false)]);

  Future<bool> play() async {
    if (!_hasSource) return false;
    final intent = _nextIntent();
    final source = _sourceGeneration;
    var played = false;
    await _enqueue(() async {
      if (!_current(intent, source)) return;
      _applying++;
      try {
        if (!await _authorize()) {
          if (_current(intent, source)) await _denyPlayback();
          return;
        }
        if (!_current(intent, source)) return;
        _expected = null;
        await target.play().timeout(commandTimeout);
        if (!_current(intent, source)) return;
        _publish(target.snapshot, changed: true);
        played = true;
      } finally {
        _applying--;
      }
    });
    return played;
  }

  Future<void> pause() =>
      _localCommand(seek: false, command: () => target.pause());

  Future<void> seek(Duration position) => _localCommand(
    seek: true,
    command: () =>
        target.seek(position < Duration.zero ? Duration.zero : position),
  );

  Future<void> _localCommand({
    required bool seek,
    required Future<void> Function() command,
  }) {
    if (!_hasSource) return Future<void>.value();
    final intent = _nextIntent();
    final source = _sourceGeneration;
    return _enqueue(() async {
      if (!_current(intent, source)) return;
      _applying++;
      try {
        _expected = null;
        await command().timeout(commandTimeout);
        if (_current(intent, source)) {
          _publish(target.snapshot, changed: true, seek: seek);
        }
      } finally {
        _applying--;
      }
    });
  }

  Future<void> _denyPlayback() async {
    await target.pause().timeout(commandTimeout);
    _expected = null;
    _publish(target.snapshot, changed: true);
  }

  /// The controller calls this when the last peer leaves. Connection loss
  /// invokes it automatically; reconnect never resumes playback by itself.
  Future<void> peerLeft() async {
    if (!_hasSource) return;
    await pause();
  }

  Future<void> _enqueue(Future<void> Function() command) {
    final operation = _tail.then((_) => command());
    // Keep the queue usable after a failed native command; the caller still
    // receives the failure and the UI receives it through onError.
    _tail = operation.catchError((Object error) {
      try {
        if (!_disposed) onError?.call(error);
      } catch (_) {
        /* Diagnostic only. */
      }
    });
    return operation;
  }

  void _background(Future<void> operation) {
    unawaited(operation.catchError((Object _) {}));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _nextIntent();
    _sourceGeneration++;
    await _playerSub?.cancel();
    await _peerSub?.cancel();
    await _connectionSub?.cancel();
    // Target and SyncCore are owned by the session controller.
  }
}
