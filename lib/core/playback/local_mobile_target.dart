import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../media/media_item.dart';
import 'playback_target.dart';

class LocalMobileTarget extends PlaybackTarget
    implements PlaybackRateTarget, PlaybackInterruptionTarget {
  LocalMobileTarget({
    bool mixWithOthers = false,
    this.rateCommandTimeout = const Duration(seconds: 5),
    Future<void> Function(int playerId, bool required)?
    configureInterruptionPolicy,
  }) : _options = VideoPlayerOptions(
         mixWithOthers: mixWithOthers,
         allowBackgroundPlayback: true,
       ),
       _configureInterruptionPolicy =
           configureInterruptionPolicy ?? _configureAndroidInterruptionPolicy;

  VideoPlayerController? _controller;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  final _focusInterruptions = StreamController<int>.broadcast(sync: true);
  static const _focusChannel = MethodChannel(
    'com.meowwatch.mobile/player_focus',
  );
  static final Map<int, LocalMobileTarget> _focusTargets = {};
  int? _activePlayerId;
  int _lastFocusInterruptionVersion = 0;
  int _loadGeneration = 0;
  int _positionGeneration = 0;
  Duration? _pausedPosition;
  bool _closed = false;
  bool _playRequested = false;
  Future<void> _rateTail = Future<void>.value();
  final Duration rateCommandTimeout;
  final Future<void> Function(int playerId, bool required)
  _configureInterruptionPolicy;
  final Set<Object> _explicitResumeOwners = Set<Object>.identity();
  Future<void> _policyTail = Future<void>.value();
  VideoPlayerController? _policyController;
  bool? _appliedExplicitResume;

  static void _registerFocusTarget(int playerId, LocalMobileTarget target) {
    if (_focusTargets.isEmpty) {
      _focusChannel.setMethodCallHandler(_dispatchFocusInterruption);
    }
    _focusTargets[playerId] = target;
    target._activePlayerId = playerId;
    target._lastFocusInterruptionVersion = 0;
  }

  static void _unregisterFocusTarget(LocalMobileTarget target) {
    final playerId = target._activePlayerId;
    if (playerId == null) return;
    if (identical(_focusTargets[playerId], target)) {
      _focusTargets.remove(playerId);
    }
    target._activePlayerId = null;
    if (_focusTargets.isEmpty) _focusChannel.setMethodCallHandler(null);
  }

  static Future<void> _dispatchFocusInterruption(MethodCall call) async {
    if (call.method != 'onFocusInterruption') return;
    final data = call.arguments;
    if (data is! Map || data.length != 2) return;
    final playerId = data['playerId'];
    final version = data['interruptionVersion'];
    if (playerId is! int || playerId <= 0 || version is! int || version <= 0) {
      return;
    }
    _focusTargets[playerId]?._acceptFocusInterruption(playerId, version);
  }

  void _acceptFocusInterruption(int playerId, int version) {
    if (_closed ||
        _activePlayerId != playerId ||
        _controller == null ||
        version <= _lastFocusInterruptionVersion) {
      return;
    }
    _lastFocusInterruptionVersion = version;
    _positionGeneration++;
    _playRequested = false;
    // Local Mode keeps the native focus policy's transient auto-resume, but
    // its controls must still reflect the immediate loss of play intent.
    if (_explicitResumeOwners.isNotEmpty) _focusInterruptions.add(version);
    notifyListeners();
  }

  static Future<void> _configureAndroidInterruptionPolicy(
    int playerId,
    bool required,
  ) async {
    if (!Platform.isAndroid) return;
    await const MethodChannel(
      'com.meowwatch.mobile/player_focus',
    ).invokeMethod<void>('setRequireExplicitResume', {
      'playerId': playerId,
      'required': required,
    });
  }

  @override
  Future<void> requireExplicitResume(Object owner) {
    if (_closed) return Future<void>.value();
    _explicitResumeOwners.add(owner);
    return _applyInterruptionPolicy(_controller);
  }

  @override
  Future<void> releaseExplicitResume(Object owner) {
    if (!_explicitResumeOwners.remove(owner) || _closed) {
      return Future<void>.value();
    }
    return _applyInterruptionPolicy(_controller);
  }

  Future<void> _applyInterruptionPolicy(VideoPlayerController? controller) {
    if (controller == null || _closed) return Future<void>.value();
    final operation = _policyTail.then((_) async {
      while (!_closed && identical(controller, _controller)) {
        final required = _explicitResumeOwners.isNotEmpty;
        if (identical(_policyController, controller) &&
            _appliedExplicitResume == required) {
          return;
        }
        // This pinned extension addresses video_player 2.14.0's native player.
        // Its ID accessor is public but test-annotated; isolate that dependency
        // here and verify compatibility through the native integration gates.
        // ignore: invalid_use_of_visible_for_testing_member
        final playerId = controller.playerId;
        await _configureInterruptionPolicy(
          playerId,
          required,
        ).timeout(const Duration(seconds: 5));
        if (_closed || !identical(controller, _controller)) return;
        _policyController = controller;
        _appliedExplicitResume = required;
        // A new room may acquire the policy while a Local Mode update is in
        // flight. Confirm the latest requirement before releasing waiting Play.
      }
    });
    // A failed policy remains unapplied; the next Play retries it and cannot
    // start native playback unless the required policy is confirmed.
    _policyTail = operation.catchError((Object _) {});
    return operation;
  }

  // MainApp owns lifecycle pause. The plugin's lifecycle observer otherwise
  // restores its remembered play state on resume and can undo that pause.
  final VideoPlayerOptions _options;

  @override
  String get id => 'phone';
  @override
  String get label => 'This phone';
  @override
  PlaybackSnapshot get snapshot => _snapshot;
  @override
  // Buffering can end before the native isPlaying update arrives.
  bool get playRequested => _snapshot.ready && _playRequested;
  @override
  bool get canReloadAfterConnectionLoss => true;
  @override
  Stream<PlaybackSnapshot> get states => _states.stream;
  @override
  Stream<int> get focusInterruptions => _focusInterruptions.stream;
  VideoPlayerController? get controller => _controller;

  void _publish(PlaybackSnapshot state) {
    if (_closed) return;
    _snapshot = state;
    _states.add(state);
    notifyListeners();
  }

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final knownDuration = _snapshot.media?.uri == media.uri
        ? _snapshot.duration
        : Duration.zero;
    final generation = ++_loadGeneration;
    _positionGeneration++;
    _pausedPosition = null;
    _playRequested = false;
    final old = _controller;
    _controller = null;
    _unregisterFocusTarget(this);
    _publish(
      PlaybackSnapshot(
        media: media,
        position: position,
        duration: knownDuration,
        connection: PlaybackConnection.loading,
      ),
    );
    if (old != null) await old.dispose();
    if (generation != _loadGeneration || _closed) return;
    final next = switch (media.uri.scheme) {
      'http' || 'https' => VideoPlayerController.networkUrl(
        media.uri,
        videoPlayerOptions: _options,
      ),
      'content' => VideoPlayerController.contentUri(
        media.uri,
        videoPlayerOptions: _options,
      ),
      'file' => VideoPlayerController.file(
        File.fromUri(media.uri),
        videoPlayerOptions: _options,
      ),
      _ => throw const FormatException(
        'Choose a video file or direct media link.',
      ),
    };
    try {
      await next.initialize().timeout(const Duration(seconds: 25));
      if (generation != _loadGeneration || _closed) {
        await next.dispose();
        return;
      }
      _controller = next;
      // ignore: invalid_use_of_visible_for_testing_member
      _registerFocusTarget(next.playerId, this);
      await _applyInterruptionPolicy(next);
      if (generation != _loadGeneration || _closed) return;
      if (position > Duration.zero) {
        await next.seekTo(
          position > next.value.duration ? next.value.duration : position,
        );
      }
      if (generation != _loadGeneration || _closed) return;
      // Native buffering events may arrive while the initial seek is pending.
      // Keep the requested loading clock until the restored position is ready.
      next.addListener(_onPlayerChanged);
      _onPlayerChanged();
    } catch (_) {
      await next.dispose();
      if (generation != _loadGeneration || _closed) return;
      _controller = null;
      _unregisterFocusTarget(this);
      _publish(
        PlaybackSnapshot(
          media: media,
          position: position,
          duration: knownDuration,
          connection: PlaybackConnection.failed,
          error: media.isNetwork
              ? 'Could not open this video. Check your connection and use a direct video link, not a webpage.'
              : 'Could not open this file. Choose it again, or try a video format supported by your device.',
        ),
      );
      rethrow;
    }
  }

  void _onPlayerChanged() {
    final value = _controller?.value;
    if (value == null) return;
    // video_player replaces the entire native value with a 0/0 erroneous
    // value. The previous snapshot is the last confirmed media clock.
    final position = value.hasError
        ? _pausedPosition ?? _snapshot.position
        : _pausedPosition ?? value.position;
    final duration = value.hasError ? _snapshot.duration : value.duration;
    if (value.hasError || value.isCompleted) {
      _playRequested = false;
    } else if (value.isPlaying) {
      // A buffered position/value update may still carry the pre-interruption
      // playing bit. Only a new native playing transition can resume its intent.
      if (!_snapshot.playing) _playRequested = true;
    } else if (!value.isBuffering && !_snapshot.buffering) {
      _playRequested = false;
    }
    _publish(
      PlaybackSnapshot(
        media: _snapshot.media,
        // A position poll started before pause can complete after the final
        // native pause read. Keep that confirmed position until a new command.
        position: position,
        duration: duration,
        playing: value.isPlaying,
        buffering: value.isBuffering,
        connection: value.hasError
            ? PlaybackConnection.failed
            : PlaybackConnection.ready,
        error: value.hasError
            ? 'Playback stopped. Try opening the video again.'
            : null,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!_snapshot.ready) throw StateError('Open a video before playing.');
    final commandGeneration = ++_positionGeneration;
    final controller = _controller!;
    await _applyInterruptionPolicy(controller);
    if (_closed ||
        commandGeneration != _positionGeneration ||
        !identical(controller, _controller)) {
      return;
    }
    final pausedPosition = _pausedPosition;
    if (pausedPosition != null) {
      // Resume from the confirmed pause cache, even if an old poll arrived.
      // Updating the controller value does not seek the native player.
      controller.value = controller.value.copyWith(position: pausedPosition);
    }
    _pausedPosition = null;
    _playRequested = true;
    await controller.play();
  }

  @override
  Future<void> pause() async {
    final generation = ++_positionGeneration;
    final controller = _controller;
    _playRequested = false;
    if (controller == null) return;
    await controller.pause();
    if (_closed ||
        generation != _positionGeneration ||
        !identical(controller, _controller)) {
      return;
    }
    // video_player stops polling on pause without refreshing value.position.
    // Publish the stopped native position before the sync bridge broadcasts it.
    final position = await controller.position;
    if (_closed ||
        generation != _positionGeneration ||
        !identical(controller, _controller) ||
        position == null ||
        controller.value.hasError) {
      return;
    }
    _pausedPosition = position < Duration.zero
        ? Duration.zero
        : position > controller.value.duration
        ? controller.value.duration
        : position;
    _onPlayerChanged();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_snapshot.ready) return;
    _positionGeneration++;
    _pausedPosition = null;
    await _controller!.seekTo(
      position < Duration.zero
          ? Duration.zero
          : position > _snapshot.duration
          ? _snapshot.duration
          : position,
    );
  }

  @override
  Future<void> setPlaybackRate(double rate) {
    final controller = _controller;
    if (_closed || controller == null || !_snapshot.ready) {
      return Future<void>.value();
    }
    // Serialize native rate calls so a late slowdown cannot follow a reset.
    final operation = _rateTail.then((_) async {
      if (_closed || !identical(controller, _controller)) return;
      await controller.setPlaybackSpeed(rate).timeout(rateCommandTimeout);
    });
    _rateTail = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _explicitResumeOwners.clear();
    _unregisterFocusTarget(this);
    _policyController = null;
    _loadGeneration++;
    _positionGeneration++;
    _pausedPosition = null;
    await _controller?.dispose();
    _controller = null;
    await _states.close();
    await _focusInterruptions.close();
    super.dispose();
  }
}
