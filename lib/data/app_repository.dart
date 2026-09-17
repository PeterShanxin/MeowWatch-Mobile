import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/connect/room_config.dart';
import '../core/media/media_item.dart';

class RoomTicket {
  const RoomTicket({
    required this.id,
    required this.config,
    required this.isHost,
  });
  final String id;
  final RoomConfig config;
  final bool isHost;
  String get contextKey => '${config.server}:${config.port}/${config.room}';

  Map<String, Object?> toJson() => {
    'id': id,
    'server': config.server,
    'port': config.port,
    'room': config.room,
    'username': config.username,
    'isHost': isHost,
  };

  factory RoomTicket.fromJson(Map<String, dynamic> json) => RoomTicket(
    id: json['id'] as String,
    isHost: json['isHost'] as bool,
    config: RoomConfig(
      server: json['server'] as String,
      port: json['port'] as int,
      room: json['room'] as String,
      username: json['username'] as String,
    ),
  );
}

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.media,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.room,
  });
  final MediaItem media;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final RoomTicket? room;
  String get key => '${room?.contextKey ?? 'local'}|${media.uri}';

  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
    'room': room?.toJson(),
  };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WatchHistoryEntry(
        media: MediaItem.fromJson(json['media'] as Map<String, dynamic>),
        position: Duration(milliseconds: json['position'] as int),
        duration: Duration(milliseconds: json['duration'] as int),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        room: json['room'] == null
            ? null
            : RoomTicket.fromJson(json['room'] as Map<String, dynamic>),
      );
}

class AppRepository {
  AppRepository(this.file);
  final File file;
  String? displayName;
  String theme = 'cozy';
  RoomTicket? activeRoom;
  final List<WatchHistoryEntry> _history = [];
  Future<void> _writes = Future.value();
  List<WatchHistoryEntry> get history => List.unmodifiable(_history);

  static Future<AppRepository> open() async {
    final directory = await getApplicationSupportDirectory();
    final repository = AppRepository(
      File('${directory.path}/watch_history.json'),
    );
    await repository.read();
    return repository;
  }

  Future<void> read() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported saved history version.');
    }
    displayName = data['displayName'] as String?;
    theme = data['theme'] as String? ?? 'cozy';
    activeRoom = data['activeRoom'] == null
        ? null
        : RoomTicket.fromJson(data['activeRoom'] as Map<String, dynamic>);
    _history
      ..clear()
      ..addAll(
        (data['history'] as List).map(
          (e) => WatchHistoryEntry.fromJson(e as Map<String, dynamic>),
        ),
      );
  }

  Future<void> record(WatchHistoryEntry entry) {
    _history.removeWhere((item) => item.key == entry.key);
    _history.insert(0, entry);
    if (_history.length > 30) _history.removeRange(30, _history.length);
    return save();
  }

  Future<void> removeHistory(String key) {
    _history.removeWhere((item) => item.key == key);
    return save();
  }

  Future<void> save() {
    final json = jsonEncode({
      'version': 1,
      'displayName': displayName,
      'theme': theme,
      'activeRoom': activeRoom?.toJson(),
      'history': _history.map((e) => e.toJson()).toList(),
    });
    final task = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final staging = File('${file.path}.tmp');
      await staging.writeAsString(json, flush: true);
      await staging.rename(file.path);
    });
    _writes = task.catchError((Object _) {});
    return task;
  }
}
