import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';

void main() {
  test('progress stays scoped to actual room and survives reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'meowwatch-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/history.json');
    final repository = AppRepository(file);
    final media = MediaItem(
      uri: Uri.parse('content://videos/42'),
      title: 'Movie',
    );
    final room = RoomTicket(
      id: 'persistent-session',
      config: const RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'cozy-cat',
        username: 'Cat',
      ),
      isHost: true,
    );
    repository.activeRoom = room;
    await repository.record(
      WatchHistoryEntry(
        media: media,
        position: const Duration(seconds: 123),
        duration: const Duration(minutes: 10),
        updatedAt: DateTime(2026, 9, 16),
        room: room,
      ),
    );
    await repository.record(
      WatchHistoryEntry(
        media: media,
        position: const Duration(seconds: 9),
        duration: const Duration(minutes: 10),
        updatedAt: DateTime(2026, 9, 16),
      ),
    );
    final restored = AppRepository(file);
    await restored.read();
    expect(restored.history, hasLength(2));
    expect(restored.history.first.position.inSeconds, 9);
    expect(restored.history.last.position.inSeconds, 123);
    expect(restored.activeRoom?.id, 'persistent-session');
    expect(restored.history.last.room?.isHost, isTrue);
  });

  test('concurrent writes preserve latest profile and progress', () async {
    final directory = await Directory.systemTemp.createTemp(
      'meowwatch-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = AppRepository(File('${directory.path}/history.json'));
    repository.displayName = 'Old';
    final first = repository.save();
    repository.displayName = 'New';
    await Future.wait([first, repository.save()]);
    final restored = AppRepository(repository.file);
    await restored.read();
    expect(restored.displayName, 'New');
  });
}
