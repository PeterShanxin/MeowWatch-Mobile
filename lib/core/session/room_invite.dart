import '../connect/room_config.dart';
import '../connect/room_share.dart';
import '../sync/syncplay_constants.dart';

Uri encodeRoomInvite(RoomConfig config) => Uri(
  scheme: 'meowwatch',
  host: 'join',
  queryParameters: {
    'room': config.room,
    'server': config.server,
    'port': '${config.port}',
  },
);

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
