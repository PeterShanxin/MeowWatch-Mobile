import 'package:nearby_bridge/nearby_bridge.dart';

import '../connect/room_config.dart';
import '../media/media_item.dart';
import '../playback/playback_target.dart';
import '../sync/peer_state.dart';

/// A companion snapshot describes the desktop; it never grants phone file access.
class NearbySnapshot {
  const NearbySnapshot({
    required this.desktopId,
    required this.desktopName,
    required this.epoch,
    required this.username,
    required this.connection,
    required this.playback,
    required this.participants,
    required this.messages,
    this.room,
  });

  final String desktopId, desktopName, epoch, username;
  final SyncConnectionStatus connection;
  final RoomConfig? room;
  final PlaybackSnapshot playback;
  final Set<String> participants;
  final List<ChatMessage> messages;

  factory NearbySnapshot.parse(Map<String, Object?> value) {
    final desktop = _map(value['desktop']);
    final session = _map(value['session']);
    final video = _map(value['playback']);
    final desktopId = _text(desktop, 'id');
    decodeBytes(desktopId, 16);
    final epoch = _text(session, 'epoch');
    decodeBytes(epoch, 16);
    final name = _text(desktop, 'name', max: 64);
    validateName(name);
    // These metadata extensions are absent in the current desktop adapter.
    // Validate them when advertised without making older v1 snapshots unusable.
    if (desktop.containsKey('protocolVersion')) {
      _integer(desktop, 'protocolVersion', min: 1, max: 1);
    }
    if (desktop.containsKey('capabilities')) {
      for (final capability in _list(desktop['capabilities'], 256)) {
        _text({'value': capability}, 'value', max: 64);
      }
    }
    if (video.containsKey('revision')) {
      _integer(video, 'revision', max: maxSafeInteger);
    }
    if (video.containsKey('sampledAtUnixMs')) {
      _integer(video, 'sampledAtUnixMs', max: 8640000000000000);
    }
    if (video['error'] != null) _text(video, 'error');
    final mode = _text(session, 'mode');
    if (mode != 'local' && mode != 'synced') _invalid();
    final username = session['username'] == null
        ? name
        : _text(session, 'username', max: 150);
    RoomConfig? room;
    if (mode == 'synced') {
      room = RoomConfig(
        room: _text(session, 'room'),
        server: _text(session, 'server'),
        port: _integer(session, 'port', min: 1, max: 65535),
        username: username,
      );
    }
    final connection = switch (session['connection']) {
      'connected' => SyncConnectionStatus.connected,
      'connecting' => SyncConnectionStatus.connecting,
      'handshaking' => SyncConnectionStatus.handshaking,
      'reconnecting' => SyncConnectionStatus.reconnecting,
      'disconnected' => SyncConnectionStatus.disconnected,
      _ => _invalid(),
    };
    MediaItem? media;
    if (video['media'] != null) {
      final item = _map(video['media']);
      if (item.containsKey('kind')) _text(item, 'kind', max: 64);
      if (item.containsKey('shareableUrl')) _text(item, 'shareableUrl');
      // The opaque URI identifies UI state only. It is never persisted as a
      // resumable phone file or passed to a local video controller.
      media = MediaItem(
        uri: Uri(
          scheme: 'meowwatch-desktop',
          host: desktopId,
          pathSegments: [_text(item, 'id')],
        ),
        title: _text(item, 'title'),
      );
    }
    final ready = video['status'] == 'ready' && media != null;
    final playback = PlaybackSnapshot(
      media: media,
      position: Duration(
        milliseconds: _integer(video, 'positionMs', max: _weekMs),
      ),
      duration: Duration(
        milliseconds: video['durationMs'] == null
            ? 0
            : _integer(video, 'durationMs', max: _weekMs),
      ),
      playing: _boolean(video, 'playing') && ready,
      buffering: video.containsKey('buffering')
          ? _boolean(video, 'buffering')
          : false,
      connection: switch (video['status']) {
        'ready' => ready ? PlaybackConnection.ready : PlaybackConnection.idle,
        'loading' => PlaybackConnection.loading,
        'disconnected' => PlaybackConnection.disconnected,
        'failed' => PlaybackConnection.failed,
        'idle' => PlaybackConnection.idle,
        _ => _invalid(),
      },
      error: video['error'] == null
          ? null
          : 'Check the video on your desktop, then try again.',
    );
    final participants = <String>{};
    for (final item in _list(value['participants'], 256)) {
      final person = _map(item);
      final username = _text(person, 'username', max: 150);
      if (person.containsKey('ready')) _boolean(person, 'ready');
      if (person.containsKey('mediaTitle')) _text(person, 'mediaTitle');
      if (!_boolean(person, 'isSelf')) {
        participants.add(username);
      }
    }
    final messages = <ChatMessage>[];
    for (final item in _list(value['chat'], 100)) {
      final chat = _map(item);
      if (chat.containsKey('id')) _text(chat, 'id', max: 64);
      messages.add(
        ChatMessage(
          username: _text(chat, 'username', max: 150),
          text: _text(chat, 'text', allowEmpty: true),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            _integer(chat, 'receivedAtUnixMs', max: 8640000000000000),
          ),
          system: _boolean(chat, 'system'),
          isMine: _boolean(chat, 'isMine'),
        ),
      );
    }
    return NearbySnapshot(
      desktopId: desktopId,
      desktopName: name,
      epoch: epoch,
      username: username,
      connection: connection,
      room: room,
      playback: playback,
      participants: Set.unmodifiable(participants),
      messages: List.unmodifiable(messages),
    );
  }
}

const _weekMs = 7 * 24 * 60 * 60 * 1000;
Never _invalid() => throw const NearbyException('invalid_argument');
Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _invalid();
List<Object?> _list(Object? value, int max) =>
    value is List<Object?> && value.length <= max ? value : _invalid();
String _text(
  Map<String, Object?> map,
  String key, {
  int max = 4096,
  bool allowEmpty = false,
}) {
  final value = map[key];
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > max ||
      value.runes.any((r) => r == 0)) {
    _invalid();
  }
  return value;
}

int _integer(
  Map<String, Object?> map,
  String key, {
  int min = 0,
  required int max,
}) {
  final value = map[key];
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

bool _boolean(Map<String, Object?> map, String key) =>
    map[key] is bool ? map[key]! as bool : _invalid();
