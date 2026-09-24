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
  bool? _publishedPaused;
  bool _buffering = false;
  Timer? _bufferRecovery;
  bool _externalPlayPending = false;
  int? _pauseCorrectionSource;
  _PlayStartCatchUp? _playStartCatchUp;
  Timer? _rateExpiry;
  Stopwatch? _rateWindow;
  Stopwatch? _rateCooldown;
  double _requestedRate = 1;
  bool _rateTouched = false;
  bool _rateDirty = false;
  bool _rateResetPending = false;
  int _rateResetAttempts = 0;
  Timer? _rateResetRetry;
  int _rateGeneration = 0;

  /// Keep the accepted room intent through transient native buffering events.
  bool get playRequested => _hasSource && _publishedPaused == false;

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
      if (!connected) _stopRateCorrection();
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
    _publishedPaused = null;
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
    // A heartbeat received during native loading may refer to the prior file.
    // Wait for fresh advancing room samples before changing decoder speed.
    sync.lastAdvancingRoomState = null;
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
        fromSourceOpen: true,
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
    _stopRateCorrection();
    sync.lastAdvancingRoomState = null;
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
    if (!_hasSource) return;
    // ExoPlayer's isPlaying is false while buffering even when playWhenReady
    // remains true. A heartbeat with that false flag would pause the room.
    if (state.buffering) {
      _stopRateCorrection();
      _buffering = true;
      _bufferRecovery?.cancel();
      _bufferRecovery = null;
      return;
    }
    if (_applying != 0) return;
    if (!state.playing || state.connection != PlaybackConnection.ready) {
      _stopRateCorrection();
    }
    if (_buffering) {
      if (!state.playing && _publishedPaused == false) {
        // READY/bufferingEnd precedes the matching isPlaying callback. Wait
        // only for that event to settle; a persistent native pause still wins.
        _bufferRecovery ??= Timer(settleWindow, () {
          _resetBuffering();
          _onPlayer(target.snapshot);
        });
        return;
      }
      _resetBuffering();
    }
    if (state.playing &&
        _publishedPaused == true &&
        !target.acceptsExternalPlaybackChanges) {
      // Phone controls enter through this bridge. A conflicting native play
      // state is therefore a delayed player/lifecycle echo, not a new intent.
      _reassertPause();
      return;
    }
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
    if (_playStartCatchUp != null &&
        (state.connection != PlaybackConnection.ready ||
            (state.duration > Duration.zero &&
                state.position >= state.duration) ||
            !state.playing)) {
      _clearPlayStartCatchUp();
    }
    if (_maybeCatchUpPlayStart(state)) return;
    if (state.playing && _publishedPaused == true) {
      // First reject stale native echoes of an expected peer command above.
      // TV remotes and system controls then pass the same quota boundary as
      // play(), keeping the paused heartbeat until authorization completes.
      if (!_externalPlayPending) {
        _externalPlayPending = true;
        _background(
          _play(externallyStarted: true).then<void>((_) {}).whenComplete(() {
            _externalPlayPending = false;
          }),
        );
      }
      return;
    }
    _considerRateCorrection(state);
    _publish(state, changed: false);
  }

  void _considerRateCorrection(PlaybackSnapshot state) {
    if (target is! PlaybackRateTarget ||
        !_connected ||
        !_hasSource ||
        !state.playing ||
        state.buffering ||
        _publishedPaused != false ||
        _playStartCatchUp != null) {
      _stopRateCorrection();
      return;
    }
    final room = sync.lastAdvancingRoomState;
    final age = sync.lastAdvancingRoomStateAge;
    if (room == null ||
        age == null ||
        age >= const Duration(seconds: 2) ||
        room.paused ||
        room.doSeek ||
        room.setBy == null) {
      _stopRateCorrection();
      return;
    }
    final ahead = state.position - (room.position + age);
    if (ahead < const Duration(milliseconds: 450) ||
        ahead >= const Duration(seconds: 4)) {
      _stopRateCorrection(cooldown: ahead < const Duration(milliseconds: 450));
      return;
    }
    // A failed native 1x command leaves the actual speed uncertain. Do not
    // issue another slowdown until restoration has succeeded.
    if (_rateDirty && _requestedRate == 1) return;
    if (_requestedRate == 1) {
      if (ahead < const Duration(milliseconds: 900) ||
          (_rateCooldown?.elapsed ?? const Duration(days: 1)) <
              const Duration(seconds: 8)) {
        return;
      }
      _rateWindow = Stopwatch()..start();
    } else if ((_rateWindow?.elapsed ?? Duration.zero) >=
        const Duration(seconds: 25)) {
      _stopRateCorrection(cooldown: true);
      return;
    }
    _rateExpiry?.cancel();
    _rateExpiry = Timer(const Duration(seconds: 2) - age, () {
      _stopRateCorrection();
    });
    // One-sided only: never speed up the lagging player. Larger safe drift
    // gets a short 0.90 window; near convergence uses the gentler 0.95 rate.
    _requestRate(ahead >= const Duration(milliseconds: 1500) ? 0.90 : 0.95);
  }

  void _requestRate(double rate) {
    if (target is! PlaybackRateTarget) return;
    if (rate == 1) {
      if (_requestedRate != 1) _rateGeneration++;
      _requestedRate = 1;
      _queueRateReset();
      return;
    }
    if (_rateDirty && _requestedRate == 1) return;
    if (_requestedRate == rate) return;
    _rateGeneration++;
    _requestedRate = rate;
    _rateTouched = true;
    _rateDirty = true;
    final generation = _rateGeneration;
    final source = _sourceGeneration;
    final intent = _intent;
    final rateTarget = target as PlaybackRateTarget;
    _background(
      _enqueue(() async {
        if (!_current(intent, source) ||
            generation != _rateGeneration ||
            _requestedRate != rate) {
          return;
        }
        await rateTarget.setPlaybackRate(rate).timeout(commandTimeout);
      }).catchError((Object _) {
        if (!_disposed && _requestedRate == rate) _stopRateCorrection();
      }),
    );
  }

  void _queueRateReset() {
    if (!_rateDirty ||
        _rateResetPending ||
        _rateResetRetry != null ||
        _rateResetAttempts >= 3 ||
        target is! PlaybackRateTarget) {
      return;
    }
    _rateResetPending = true;
    _rateResetAttempts++;
    final generation = _rateGeneration;
    final rateTarget = target as PlaybackRateTarget;
    _background(
      _enqueue(() {
        if (_disposed || generation != _rateGeneration) {
          return Future<void>.value();
        }
        return rateTarget.setPlaybackRate(1).timeout(commandTimeout);
      }).then<void>(
        (_) {
          if (_disposed || generation != _rateGeneration) return;
          _rateResetPending = false;
          _rateDirty = false;
          _rateResetAttempts = 0;
          _rateResetRetry?.cancel();
          _rateResetRetry = null;
        },
        onError: (Object _) {
          if (generation != _rateGeneration) return;
          _rateResetPending = false;
          if (_disposed || _rateResetAttempts >= 3) return;
          _rateResetRetry = Timer(
            Duration(milliseconds: 200 * _rateResetAttempts),
            () {
              _rateResetRetry = null;
              if (!_disposed && _requestedRate == 1) _queueRateReset();
            },
          );
        },
      ),
    );
  }

  void _stopRateCorrection({bool cooldown = false}) {
    _rateExpiry?.cancel();
    _rateExpiry = null;
    _rateWindow = null;
    if (cooldown && _requestedRate != 1) {
      _rateCooldown = Stopwatch()..start();
    }
    _requestRate(1);
  }

  void _reassertPause() {
    final source = _sourceGeneration;
    if (_pauseCorrectionSource == source) return;
    _pauseCorrectionSource = source;
    _background(
      _enqueue(() async {
        if (!_hasSource ||
            source != _sourceGeneration ||
            _publishedPaused != true) {
          return;
        }
        _applying++;
        try {
          await target.pause().timeout(commandTimeout);
          if (!_hasSource ||
              source != _sourceGeneration ||
              _publishedPaused != true) {
            return;
          }
          final expected = _expected;
          if (expected != null && expected.paused) {
            _acknowledge(expected);
          } else {
            _publish(target.snapshot, changed: false, paused: true);
          }
        } finally {
          _applying--;
        }
      }).whenComplete(() {
        if (_pauseCorrectionSource == source) {
          _pauseCorrectionSource = null;
        }
      }),
    );
  }

  void _publish(
    PlaybackSnapshot state, {
    required bool changed,
    bool seek = false,
    bool? paused,
  }) {
    if (!_hasSource) return;
    if (state.buffering) _buffering = true;
    _publishedPaused = paused ?? !state.playing;
    sync.updateLocalState(position: state.position, paused: _publishedPaused!);
    if (changed) sync.notifyLocalChange(doSeek: seek);
  }

  void _acknowledge(PeerPlayState state) {
    _expected = state;
    _publishedPaused = state.paused;
    _expectedAt = DateTime.now();
    // Synchronous acknowledgement is required before Syncplay replies to the
    // current State. Native player commands may complete much later.
    sync.updateLocalState(position: state.position, paused: state.paused);
  }

  void _onPeer(PeerPlayState peer, {bool fromSourceOpen = false}) {
    if (_disposed) return;
    final firstPlay =
        _hasSource &&
        (_publishedPaused == true || fromSourceOpen) &&
        (!target.snapshot.playing || fromSourceOpen) &&
        !peer.paused &&
        (!peer.doSeek || fromSourceOpen);
    _latestPeer = peer;
    _acknowledge(peer);
    if (!_hasSource) return;
    final intent = _nextIntent();
    final source = _sourceGeneration;
    final watch = firstPlay ? _watchPlayStart(peer, intent, source) : null;
    _background(
      _enqueue(() async {
        if (!_current(intent, source)) return;
        _applying++;
        try {
          if (!peer.paused && !await _authorize()) {
            if (watch != null && identical(_playStartCatchUp, watch)) {
              _clearPlayStartCatchUp();
            }
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
            if (watch != null && identical(_playStartCatchUp, watch)) {
              _clearPlayStartCatchUp();
            }
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

  _PlayStartCatchUp _watchPlayStart(
    PeerPlayState peer,
    int intent,
    int source,
  ) {
    final watch = _PlayStartCatchUp(peer, intent, source);
    _playStartCatchUp = watch;
    return watch;
  }

  bool _maybeCatchUpPlayStart(PlaybackSnapshot state) {
    final watch = _playStartCatchUp;
    if (watch == null || !_current(watch.intent, watch.source)) return false;
    if (watch.clock.elapsed > const Duration(seconds: 12)) {
      _clearPlayStartCatchUp();
      return false;
    }
    if (watch.pending) return true;
    if (!state.playing || state.buffering || _publishedPaused != false) {
      return false;
    }
    // A play() Future can finish before the decoder displays its first frame.
    // Require an advancing native position before comparing it to room time.
    if (state.position <=
        watch.resumePosition + const Duration(milliseconds: 80)) {
      return false;
    }
    final projected = _projectPlayStart(watch, state.duration);
    if (projected == null ||
        projected - state.position < const Duration(milliseconds: 750)) {
      // Initial movement can look synchronized before the decoder buffers
      // again. Keep the bounded watch for a later fresh room heartbeat.
      return false;
    }
    watch.pending = true;
    _background(
      _enqueue(() async {
        if (!identical(_playStartCatchUp, watch) ||
            !_current(watch.intent, watch.source) ||
            _publishedPaused != false ||
            watch.clock.elapsed > const Duration(seconds: 12)) {
          if (identical(_playStartCatchUp, watch)) _clearPlayStartCatchUp();
          return;
        }
        final current = target.snapshot;
        if (current.buffering) {
          watch.pending = false;
          return;
        }
        final position = _projectPlayStart(watch, current.duration);
        if (position == null ||
            !current.playing ||
            position - current.position < const Duration(milliseconds: 750)) {
          watch.pending = false;
          return;
        }
        _applying++;
        try {
          watch.corrections++;
          watch.resumePosition = position;
          await target.seek(position).timeout(commandTimeout);
          if (_current(watch.intent, watch.source) &&
              _publishedPaused == false) {
            _acknowledge(
              PeerPlayState(
                position: position,
                paused: false,
                setBy: watch.peer.setBy,
              ),
            );
          }
        } catch (_) {
          if (identical(_playStartCatchUp, watch)) _clearPlayStartCatchUp();
          rethrow;
        } finally {
          _applying--;
          watch.pending = false;
          // Seeking can itself buffer. Recheck after real movement, but allow
          // only one follow-up correction so a slow decoder cannot seek-loop.
          if (watch.corrections >= 2 && identical(_playStartCatchUp, watch)) {
            _clearPlayStartCatchUp();
          }
        }
      }),
    );
    return true;
  }

  Duration? _projectPlayStart(_PlayStartCatchUp watch, Duration duration) {
    final room = sync.lastObservedRoomState;
    final age = sync.lastObservedRoomStateAge;
    // Room playback may also stall. A fresh heartbeat is a better anchor than
    // assuming that the original Play kept advancing at wall-clock speed.
    final Duration projected;
    if (room != null && age != null && room.setBy != null) {
      if (room.paused || age > const Duration(seconds: 2)) return null;
      projected = room.position + age;
    } else {
      if (watch.clock.elapsed > const Duration(seconds: 2)) return null;
      projected = watch.peer.position + watch.clock.elapsed;
    }
    if (duration <= Duration.zero) return projected;
    // Avoid a corrective seek to EOF, which can restart or loop on some
    // players instead of completing the already-running playback.
    if (projected >= duration - const Duration(milliseconds: 250)) {
      return null;
    }
    return projected;
  }

  void _clearPlayStartCatchUp() {
    _playStartCatchUp = null;
  }

  int _nextIntent() {
    _stopRateCorrection();
    sync.lastAdvancingRoomState = null;
    _clearPlayStartCatchUp();
    _resetBuffering();
    _superseded.complete();
    _superseded = Completer<void>();
    return ++_intent;
  }

  void _resetBuffering() {
    _bufferRecovery?.cancel();
    _bufferRecovery = null;
    _buffering = false;
  }

  Future<bool> _authorize() =>
      Future.any([authorizePlayback(), _superseded.future.then((_) => false)]);

  Future<bool> play() => _play();

  Future<bool> _play({bool externallyStarted = false}) async {
    if (!_hasSource) return false;
    final intent = _nextIntent();
    final source = _sourceGeneration;
    var played = false;
    await _enqueue(() async {
      if (!_current(intent, source)) return;
      _applying++;
      try {
        if (externallyStarted) {
          await target.pause().timeout(commandTimeout);
          if (!_current(intent, source)) return;
        }
        if (!await _authorize()) {
          if (_current(intent, source)) await _denyPlayback();
          return;
        }
        if (!_current(intent, source)) return;
        _expected = null;
        await target.play().timeout(commandTimeout);
        if (!_current(intent, source)) return;
        _publish(target.snapshot, changed: true, paused: false);
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
          _publish(
            target.snapshot,
            changed: true,
            seek: seek,
            // Explicit pause always wins, including during buffering. Seek
            // keeps the accepted intent instead of mistaking a stall for pause.
            paused: seek ? _publishedPaused : true,
          );
        }
      } finally {
        _applying--;
      }
    });
  }

  Future<void> _denyPlayback() async {
    await target.pause().timeout(commandTimeout);
    _expected = null;
    _publish(target.snapshot, changed: true, paused: true);
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
    final restoreRate = _rateTouched && target is PlaybackRateTarget;
    _disposed = true;
    _rateResetRetry?.cancel();
    _rateResetRetry = null;
    _nextIntent();
    // A queued 1x command from this bridge must not land after a replacement
    // bridge starts correcting the same target. The direct restore below is
    // the final rate command this bridge is allowed to issue.
    _rateGeneration++;
    _sourceGeneration++;
    // Native commands already in the queue may still be pending. The local
    // target serializes and bounds its own rate calls, so restore directly
    // without making disposal wait for every old seek/authorization command.
    if (restoreRate) {
      try {
        await (target as PlaybackRateTarget)
            .setPlaybackRate(1)
            .timeout(commandTimeout);
      } catch (error) {
        try {
          onError?.call(error);
        } catch (_) {
          // Diagnostic only; dispose must still release its listeners.
        }
      }
    }
    await _playerSub?.cancel();
    await _peerSub?.cancel();
    await _connectionSub?.cancel();
    // Target and SyncCore are owned by the session controller.
  }
}

class _PlayStartCatchUp {
  _PlayStartCatchUp(this.peer, this.intent, this.source)
    : resumePosition = peer.position;

  final PeerPlayState peer;
  final int intent;
  final int source;
  final Stopwatch clock = Stopwatch()..start();
  Duration resumePosition;
  int corrections = 0;
  bool pending = false;
}
