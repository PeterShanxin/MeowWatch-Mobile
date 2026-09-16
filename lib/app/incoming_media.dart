import 'dart:async';

import 'package:flutter/services.dart';

import '../core/media/media_item.dart';

/// A proposal to open media, never an instruction to start playback.
class IncomingMedia {
  const IncomingMedia({
    required this.id,
    this.media,
    this.invite,
    this.durableAccess = false,
    this.error,
    this.warning,
  });

  final String id;
  final MediaItem? media;
  final Uri? invite;

  /// True only when Android confirms a persisted content read grant.
  /// Network URLs do not use a content grant and report false.
  final bool durableAccess;
  final String? error;
  final String? warning;

  static const _maxUriLength = 4096;
  static const _videoExtensions = {
    'mp4',
    'm4v',
    'mov',
    'webm',
    'mkv',
    '3gp',
    'm3u8',
    'mpd',
  };
  static const _errors = {
    'invalid_payload':
        'This share could not be opened. Share one direct video link or a video file.',
    'unsupported_media':
        'Share a direct HTTP or HTTPS video link, or a video file from an Android app.',
    'permission_denied':
        'Access to this shared video was not granted. Choose it using Open a video instead.',
  };

  factory IncomingMedia.fromPlatform(Map<Object?, Object?> value) {
    final rawId = value['id'];
    final id = rawId is String && rawId.isNotEmpty && rawId.length <= 100
        ? rawId
        : 'invalid';
    IncomingMedia invalid() =>
        IncomingMedia(id: id, error: _errors['invalid_payload']);
    if (id == 'invalid') return invalid();
    if (value['kind'] == 'error') {
      return IncomingMedia(
        id: id,
        error: _errors[value['errorCode']] ?? _errors['invalid_payload'],
      );
    }
    final rawUri = value['uri'];
    if (rawUri is! String ||
        rawUri.length > _maxUriLength ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(rawUri) ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(rawUri)) {
      return invalid();
    }
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.userInfo.isNotEmpty) return invalid();
    final overflow = value['overflow'] == true;
    const overflowWarning =
        'Several videos were shared at once. Some earlier shares were replaced; share them again if needed.';
    if (value['kind'] == 'invite') {
      if (uri.scheme != 'meowwatch' || uri.host != 'join') return invalid();
      return IncomingMedia(
        id: id,
        invite: uri,
        warning: overflow ? overflowWarning : null,
      );
    }
    if (value['kind'] != 'media') return invalid();
    final mime = value['mimeType'];
    final videoMime =
        mime is String && RegExp(r'^video/[a-zA-Z0-9.+*_-]+$').hasMatch(mime);
    MediaItem media;
    var durable = false;
    if (uri.scheme == 'content') {
      if (uri.authority.isEmpty || !videoMime || value['readAccess'] != true) {
        return invalid();
      }
      durable = value['durableAccess'] == true;
      // Provider display names may require a remote query; defer file access
      // until the user approves opening it.
      media = MediaItem(uri: uri, title: 'Shared video', canRemember: durable);
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      final extension = uri.path.toLowerCase().split('.').last;
      if (!videoMime && !_videoExtensions.contains(extension)) {
        return IncomingMedia(id: id, error: _errors['unsupported_media']);
      }
      try {
        media = MediaItem.fromUrl(rawUri);
      } on FormatException {
        return invalid();
      }
    } else {
      return invalid();
    }
    final warnings = <String>[
      if (uri.scheme == 'content' && !durable)
        'This app granted temporary video access. To keep it in Continue Watching, choose it again using Open a video.',
      if (overflow) overflowWarning,
    ];
    return IncomingMedia(
      id: id,
      media: media,
      durableAccess: durable,
      warning: warnings.isEmpty ? null : warnings.join(' '),
    );
  }
}

abstract interface class IncomingMediaSource {
  /// Consumes the bounded native queue without opening the proposed media.
  Future<List<IncomingMedia>> takePending();
  Stream<void> get changes;
}

final class AndroidIncomingMediaSource implements IncomingMediaSource {
  static const _methods = MethodChannel('com.meowwatch.mobile/incoming-media');
  static const _events = EventChannel(
    'com.meowwatch.mobile/incoming-media/events',
  );
  static final _changes = _events.receiveBroadcastStream().map<void>((_) {});

  @override
  Stream<void> get changes => _changes;

  @override
  Future<List<IncomingMedia>> takePending() async {
    final values =
        await _methods.invokeListMethod<Object?>('drain') ?? const [];
    return values
        .take(8)
        .map(
          (value) => IncomingMedia.fromPlatform(
            value is Map ? Map<Object?, Object?>.from(value) : const {},
          ),
        )
        .toList(growable: false);
  }
}

/// Delivers cold and warm proposals once; the UI owns confirmation and playback.
final class IncomingMediaInbox {
  IncomingMediaInbox(this._source);

  final IncomingMediaSource _source;
  final _seen = <String>{};
  StreamSubscription<void>? _subscription;
  Future<void>? _draining;
  bool _needsDrain = false;
  bool _closed = false;
  void Function(IncomingMedia)? _onMedia;
  void Function(Object)? _onError;

  Future<void> start({
    required void Function(IncomingMedia) onMedia,
    required void Function(Object) onError,
  }) async {
    if (_closed || _subscription != null) return;
    _onMedia = onMedia;
    _onError = onError;
    _subscription = _source.changes.listen(
      (_) => unawaited(_requestDrain()),
      onError: (Object _) {
        if (!_closed) {
          _onError?.call(
            StateError(
              'Could not receive the shared video. Try sharing it again.',
            ),
          );
        }
      },
    );
    await _requestDrain();
  }

  Future<void> _requestDrain() {
    if (_closed) return Future.value();
    _needsDrain = true;
    final active = _draining;
    if (active != null) return active;
    final complete = Completer<void>();
    _draining = complete.future;
    unawaited(_finishDrain(complete));
    return complete.future;
  }

  Future<void> _finishDrain(Completer<void> complete) async {
    try {
      do {
        await _drain();
      } while (_needsDrain && !_closed);
    } finally {
      _draining = null;
      complete.complete();
    }
  }

  Future<void> _drain() async {
    while (_needsDrain && !_closed) {
      _needsDrain = false;
      try {
        final batch = await _source.takePending();
        for (final item in batch.take(8)) {
          if (_closed) return;
          if (!_seen.add(item.id)) continue;
          if (_seen.length > 64) _seen.remove(_seen.first);
          _onMedia?.call(item);
        }
      } catch (_) {
        if (!_closed) {
          _onError?.call(
            StateError(
              'Could not receive the shared video. Try sharing it again.',
            ),
          );
        }
      }
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    _onMedia = null;
    _onError = null;
  }
}
