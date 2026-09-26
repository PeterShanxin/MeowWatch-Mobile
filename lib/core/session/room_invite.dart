import '../chat/shared_video_link.dart';
import '../connect/room_config.dart';
import '../connect/room_share.dart';
import '../media/media_item.dart';
import '../sync/syncplay_constants.dart';

/// [media] rides along only when it is a direct network link recognized by
/// [sharedVideoLink] — the same guest-facing validation used for chat-shared
/// links. Local files and unsupported links are silently left out.
Uri encodeRoomInvite(RoomConfig config, {MediaItem? media}) {
  final video = media == null ? null : sharedVideoLink(media.uri.toString());
  return Uri(
    scheme: 'meowwatch',
    host: 'join',
    queryParameters: {
      'room': config.room,
      'server': config.server,
      'port': '${config.port}',
      if (video != null) 'video': video.uri.toString(),
    },
  );
}

/// The optional direct video an invite carries, or null when absent or
/// invalid. A bad `video` parameter never invalidates the room invite itself.
MediaItem? parseInviteVideo(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri?.scheme != 'meowwatch' || uri!.host != 'join') return null;
  final video = uri.queryParameters['video'];
  if (video == null) return null;
  return sharedVideoLink(video);
}

RoomConfig parseRoomInvite(String raw, String username) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  String room;
  String server;
  int port;
  if (uri?.scheme == 'meowwatch') {
    if (uri!.host != 'join') {
      throw const FormatException('This is not a room invitation.');
    }
    room = uri.queryParameters['room'] ?? '';
    server = uri.queryParameters['server'] ?? '';
    port = int.tryParse(uri.queryParameters['port'] ?? '') ?? 0;
  } else {
    final parsed = parseShareCode(value);
    if (!parsed.isValid) throw FormatException(parsed.error!);
    room = parsed.room;
    server = parsed.server ?? SyncplayConstants.defaultServer;
    port = parsed.port ?? SyncplayConstants.publicServerPort;
  }
  if (room.isEmpty ||
      room.runes.length > 35 ||
      RegExp(r'[\x00-\x1f]').hasMatch(room)) {
    throw const FormatException('Use a room code between 1 and 35 characters.');
  }
  if (server.isEmpty ||
      server.contains(RegExp(r'[\s/@?#]')) ||
      port < 1 ||
      port > 65535) {
    throw const FormatException(
      'The invitation has an invalid server address. Ask your friend to share it again.',
    );
  }
  return RoomConfig(server: server, port: port, room: room, username: username);
}
