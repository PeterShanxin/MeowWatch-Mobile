import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import '../media/media_item.dart';
import 'playback_target.dart';

class LocalMobileTarget extends PlaybackTarget {
  LocalMobileTarget({bool mixWithOthers = false})
    : _options = VideoPlayerOptions(
        mixWithOthers: mixWithOthers,
        allowBackgroundPlayback: true,
      );

  VideoPlayerController? _controller;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  int _loadGeneration = 0;
  int _positionGeneration = 0;
  Duration? _pausedPosition;
  bool _closed = false;
  bool _playRequested = false;

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
    final generation = ++_loadGeneration;
    _positionGeneration++;
    _pausedPosition = null;
    _playRequested = false;
    final old = _controller;
    _controller = null;
    _publish(
      PlaybackSnapshot(media: media, connection: PlaybackConnection.loading),
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
        position: _pausedPosition ?? value.position,
        duration: value.duration,
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
    _positionGeneration++;
    final controller = _controller!;
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
        position == null) {
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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _loadGeneration++;
    _positionGeneration++;
    _pausedPosition = null;
    await _controller?.dispose();
    _controller = null;
    await _states.close();
    super.dispose();
  }
}
