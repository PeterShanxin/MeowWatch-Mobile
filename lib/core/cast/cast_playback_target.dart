import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../media/media_item.dart';
import '../playback/playback_target.dart';
import 'cast_transport.dart';

/// A single owned receiver session. Room membership remains on the phone.
class CastPlaybackTarget extends PlaybackTarget {
  CastPlaybackTarget({CastTransport? transport})
    : _transport = transport ?? AndroidCastTransport() {
    _subscription = _transport.events.listen(_accept, onError: _streamFailed);
  }

  final CastTransport _transport;
  static int _ownerSequence = 0;
  final String _owner =
      '${DateTime.now().microsecondsSinceEpoch}-${++_ownerSequence}';
  late final StreamSubscription<Map<Object?, Object?>> _subscription;
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  int _generation = -1;
  int _revision = -1;
  int _loadSequence = 0;
  bool _closed = false;
  bool _connecting = false;
  bool _connectRequested = false;
  bool _ownsLease = false;
  bool _superseded = false;
  String _receiverName = 'TV';
  String _sessionState = 'disconnected';
  String? _mediaToken;
  MediaItem? _media;
  Completer<void>? _loaded;

  @override
  String get id => 'cast';
  @override
  String get label => _receiverName;
  String get receiverName => _receiverName;
  String get sessionState => _sessionState;
  bool get connected => _ownsLease && _sessionState == 'connected';
  @override
  PlaybackSnapshot get snapshot => _snapshot;
  @override
  bool get acceptsExternalPlaybackChanges => true;
  @override
  Stream<PlaybackSnapshot> get states => _states.stream;

  static const unsupportedMessage =
      'Cast needs a public HTTPS link ending in .mp4, without sign-in or URL parameters. Local files and private network links cannot be cast.';

  static bool supports(MediaItem media) {
    final uri = media.uri;
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.toLowerCase().endsWith('.mp4')) {
      return false;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (!host.contains('.') ||
        host.endsWith('.local') ||
        host.endsWith('.localhost') ||
        host.endsWith('.internal') ||
        host.endsWith('.home.arpa')) {
      return false;
    }
    // IP literals are excluded entirely; receiver reachability is verified by load.
    return InternetAddress.tryParse(host) == null;
  }

  Future<void> connect({Duration timeout = const Duration(seconds: 60)}) async {
    _checkOpen();
    if (_connecting) throw StateError('The Cast chooser is already open.');
    _connecting = true;
    _connectRequested = true;
    try {
      final state = await _transport
          .invoke('connect', {'owner': _owner})
          .timeout(timeout);
      _checkOpen();
      _accept(state);
      if (!connected) throw StateError('The TV did not connect. Try again.');
    } finally {
      _connecting = false;
    }
  }

  Future<void> showChooser() async {
    _checkConnected();
    await _invoke('showChooser');
  }

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    _checkConnected();
    if (!supports(media)) throw const FormatException(unsupportedMessage);
    _failLoad(StateError('A newer video replaced this Cast request.'));
    final token = '${DateTime.now().microsecondsSinceEpoch}-${++_loadSequence}';
    _mediaToken = token;
    _media = media;
    final loaded = Completer<void>();
    _loaded = loaded;
    // Attach the error handler before an event or command failure can complete it.
    final ready = loaded.future.timeout(const Duration(seconds: 30));
    final generation = _generation;
    try {
      await Future.wait<void>([
        _invoke('load', {
          'url': media.uri.toString(),
          'contentType': 'video/mp4',
          'mediaToken': token,
          'positionMs': position.inMilliseconds.clamp(0, 1 << 53),
          'autoplay': false,
        }),
        ready,
      ], eagerError: true);
      if (_closed || generation != _generation || token != _mediaToken) {
        throw StateError('The Cast session changed while opening the video.');
      }
    } catch (_) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('The TV did not open the video.'));
      }
      if (!_closed && token == _mediaToken && generation == _generation) {
        _publish(
          PlaybackSnapshot(
            media: media,
            connection: PlaybackConnection.failed,
            error:
                'The TV could not open this video. Try another public MP4 link.',
          ),
        );
      }
      rethrow;
    } finally {
      if (identical(_loaded, loaded)) _loaded = null;
    }
  }

  @override
  Future<void> play() => _invoke('play');
  @override
  Future<void> pause() => _invoke('pause');
  @override
  Future<void> seek(Duration position) => _invoke('seek', {
    'positionMs': position.inMilliseconds.clamp(
      0,
      _snapshot.duration > Duration.zero
          ? _snapshot.duration.inMilliseconds
          : 1 << 53,
    ),
  });

  Future<void> _invoke(
    String method, [
    Map<String, Object?> extra = const {},
  ]) async {
    _checkConnected();
    final generation = _generation;
    final state = await _transport.invoke(method, {
      'generation': generation,
      'owner': _owner,
      'mediaToken': _mediaToken,
      ...extra,
    });
    _checkOpen();
    if (generation != _generation || !connected) {
      throw StateError('The Cast session changed. Reconnect to the TV.');
    }
    _accept(state);
    if (!connected) throw StateError('Cast control moved to another target.');
  }

  void _accept(Map<Object?, Object?> event) {
    if (_closed) return;
    if (_superseded && !_connecting) return;
    if (!_connecting && !_ownsLease) return;
    final generation = (event['generation'] as num?)?.toInt();
    final revision = (event['revision'] as num?)?.toInt();
    if (generation == null || revision == null || revision <= _revision) return;
    if (generation < _generation) return;
    if (event['owner'] != _owner) {
      if (_ownsLease) {
        _revision = revision;
        _retireLease();
      }
      return;
    }
    // Once bound, never adopt another receiver behind the room controller's back.
    if (_generation >= 0 && generation > _generation && !_connecting) {
      _retireLease();
      return;
    }
    _ownsLease = true;
    _generation = generation;
    _superseded = false;
    _revision = revision;
    _receiverName = event['receiverName'] as String? ?? _receiverName;
    _sessionState = event['session'] as String? ?? 'disconnected';
    if (!connected) {
      final pending = _sessionState == 'connecting';
      if (!pending) _failLoad(StateError('The TV disconnected.'));
      _publish(
        PlaybackSnapshot(
          media: _media,
          position: _snapshot.position,
          duration: _snapshot.duration,
          connection: pending
              ? PlaybackConnection.loading
              : PlaybackConnection.disconnected,
          error: pending
              ? null
              : 'The TV disconnected. Choose where to continue watching.',
        ),
      );
      return;
    }
    if (_mediaToken == null || event['mediaToken'] != _mediaToken) {
      // Never attribute another sender's video/position to our accepted source.
      if (_mediaToken != null && _loaded == null) {
        _publish(
          PlaybackSnapshot(
            media: _media,
            connection: PlaybackConnection.failed,
            error:
                'The video on the TV changed. Open your video again to continue.',
          ),
        );
      } else {
        notifyListeners();
      }
      return;
    }
    final status = event['player'] as String? ?? 'idle';
    final duration = Duration(
      milliseconds: ((event['durationMs'] as num?)?.toInt() ?? 0).clamp(
        0,
        1 << 53,
      ),
    );
    final ended = status == 'ended';
    final failed = status == 'failed';
    final ready = ['playing', 'paused', 'buffering', 'ended'].contains(status);
    _publish(
      PlaybackSnapshot(
        media: _media,
        position: ended
            ? duration
            : Duration(
                milliseconds: ((event['positionMs'] as num?)?.toInt() ?? 0)
                    .clamp(0, 1 << 53),
              ),
        duration: duration,
        playing: status == 'playing',
        buffering: status == 'buffering' || status == 'loading',
        connection: failed
            ? PlaybackConnection.failed
            : ready
            ? PlaybackConnection.ready
            : PlaybackConnection.loading,
        error: failed
            ? 'The TV could not play this video. Try another MP4 link.'
            : null,
      ),
    );
    if (ready && _loaded != null && !_loaded!.isCompleted) _loaded!.complete();
    if (failed) _failLoad(StateError('The TV could not play this video.'));
  }

  void _streamFailed(Object error) {
    if (_closed) return;
    _sessionState = 'disconnected';
    _failLoad(StateError('Cast is unavailable on this device.'));
    _publish(
      PlaybackSnapshot(
        media: _media,
        connection: PlaybackConnection.disconnected,
        error: 'Cast is unavailable. Check Google Play services and try again.',
      ),
    );
  }

  void _retireLease() {
    _ownsLease = false;
    _superseded = true;
    _sessionState = 'disconnected';
    _failLoad(StateError('The Cast session changed.'));
    _publish(
      PlaybackSnapshot(
        media: _media,
        position: _snapshot.position,
        duration: _snapshot.duration,
        connection: PlaybackConnection.disconnected,
        error: 'The Cast session ended. Choose where to continue watching.',
      ),
    );
  }

  void _failLoad(Object error) {
    final loaded = _loaded;
    if (loaded != null && !loaded.isCompleted) loaded.completeError(error);
  }

  void _checkOpen() {
    if (_closed) throw StateError('This Cast target is closed.');
  }

  void _checkConnected() {
    _checkOpen();
    if (!connected) throw StateError('Connect to a TV first.');
  }

  void _publish(PlaybackSnapshot state) {
    if (_closed) return;
    _snapshot = state;
    _states.add(state);
    notifyListeners();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failLoad(StateError('This Cast target is closed.'));
    try {
      if (_connectRequested) {
        await _transport.invoke('disconnect', {
          'generation': _generation,
          'owner': _owner,
        });
      }
    } on PlatformException catch (error) {
      // Closing is also used when Google Play services cannot initialize.
      if (error.code != 'cast_unavailable' && error.code != 'cast_closed') {
        rethrow;
      }
    } on MissingPluginException {
      // No native session exists when the Android bridge is unavailable.
    } finally {
      await _subscription.cancel();
      await _states.close();
      super.dispose();
    }
  }
}
