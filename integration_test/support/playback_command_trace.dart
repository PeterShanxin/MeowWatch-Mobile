import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// Bounded observation of real commands; no media, participant or room values.
class PlaybackCommandTrace {
  bool enabled = false;
  int _records = 0;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void record(String event, Map<String, Object?> fields) {
    if (!enabled || _records >= 160) return;
    debugPrint(
      'PRODUCTION_PLAYBACK_TRACE ${jsonEncode({'sequence': ++_records, 'atUtc': DateTime.now().toUtc().toIso8601String(), 'event': event, ...fields})}',
    );
  }

  SyncplayClient createClient() {
    final client = SyncplayClient();
    _subscriptions.add(
      client.peerState.listen((state) {
        record('room-command', {
          'paused': state.paused,
          'doSeek': state.doSeek,
          'positionMs': state.position.inMilliseconds,
        });
      }),
    );
    return client;
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

class TracedMobileTarget extends LocalMobileTarget {
  TracedMobileTarget(this.trace);
  final PlaybackCommandTrace trace;
  int _commandSequence = 0;

  Future<void> _command(String name, Future<void> Function() action) async {
    final id = ++_commandSequence;
    void record(String phase, [Object? error]) => trace.record('$name-$phase', {
      'command': id,
      'ready': snapshot.ready,
      'playing': snapshot.playing,
      'playRequested': playRequested,
      'buffering': snapshot.buffering,
      'positionMs': snapshot.position.inMilliseconds,
      if (error != null) 'errorType': error.runtimeType.toString(),
    });
    record('start');
    try {
      await action();
      record('end');
    } catch (error) {
      record('error', error);
      rethrow;
    }
  }

  @override
  Future<void> load(MediaItem media, {Duration position = Duration.zero}) =>
      _command('native-load', () => super.load(media, position: position));

  @override
  Future<void> play() => _command('native-play', super.play);

  @override
  Future<void> pause() => _command('native-pause', super.pause);

  @override
  Future<void> seek(Duration position) =>
      _command('native-seek', () => super.seek(position));
}
