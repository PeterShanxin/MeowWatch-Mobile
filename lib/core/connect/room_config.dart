import 'package:meta/meta.dart';

enum SyncplayEndpointPolicy { pinned, discover, discoverFromRoom }

/// The identity of a room plus the policy used to find its server.
/// A shared room code always pins its endpoint so friends cannot silently
/// create the same room name on two different servers.
@immutable
class RoomConfig {
  const RoomConfig({
    required this.server,
    required this.port,
    required this.room,
    required this.username,
    this.password,
    this.endpointPolicy = SyncplayEndpointPolicy.pinned,
  });

  final String server;
  final int port;
  final String room;
  final String username;
  final String? password;
  final SyncplayEndpointPolicy endpointPolicy;

  RoomConfig copyWith({
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    SyncplayEndpointPolicy? endpointPolicy,
  }) => RoomConfig(
    server: server ?? this.server,
    port: port ?? this.port,
    room: room ?? this.room,
    username: username ?? this.username,
    password: password ?? this.password,
    endpointPolicy: endpointPolicy ?? this.endpointPolicy,
  );
}
