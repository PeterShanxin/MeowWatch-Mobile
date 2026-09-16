import 'package:flutter/foundation.dart';

import '../media/media_item.dart';

enum PlaybackConnection { idle, loading, ready, disconnected, failed }

@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.media,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.connection = PlaybackConnection.idle,
    this.error,
  });

  final MediaItem? media;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final PlaybackConnection connection;
  final String? error;
  bool get ready => connection == PlaybackConnection.ready;
}

/// Every target publishes one coherent snapshot, preventing mismatched position
/// and play-state samples from separate asynchronous streams.
abstract class PlaybackTarget extends ChangeNotifier {
  String get id;
  String get label;
  PlaybackSnapshot get snapshot;
  Stream<PlaybackSnapshot> get states;
  Future<void> load(MediaItem media, {Duration position = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> close();
}
