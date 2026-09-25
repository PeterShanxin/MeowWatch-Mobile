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
        await _configureInterruptionPolicy(
          controller.playerId,
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
      await _applyInterruptionPolicy(next);
      if (generation != _loadGeneration || _closed) return;
      next.addListener(_onPlayerChanged);
      if (position > Duration.zero) {
        await next.seekTo(
          position > next.value.duration ? next.value.duration : position,
        );
      }
      _onPlayerChanged();
    } catch (_) {
      await next.dispose();
      if (generation != _loadGeneration || _closed) return;
      _controller = null;
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
      _playRequested = true;
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
    _policyController = null;
    _loadGeneration++;
    _positionGeneration++;
    _pausedPosition = null;
    await _controller?.dispose();
    _controller = null;
    await _states.close();
    super.dispose();
  }
}
