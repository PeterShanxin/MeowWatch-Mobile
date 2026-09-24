import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/sync_playback_fakes.dart';
import '../../support/syncplay_room_server.dart';

final _movie = MediaItem(
  uri: Uri.parse('https://example.com/movie.mp4'),
  title: 'Movie',
);

void main() {
  test(
    'a slow follower can become setter and needs post-rewind catch-up',
    () async {
      var roomClock = DateTime.utc(2026, 1, 1);
      final server = await SyncplayRoomServer.start(
        heartbeat: null,
        slowestWatcherAnchor: true,
        clock: () => roomClock,
      );
      final host = SyncplayClient();
      final guest = SyncplayClient();
      final hostTarget = _BufferAfterRewindTarget();
      final guestTarget = _BufferOnFirstPlayTarget();
      final hostBridge = PlaybackSyncBridge(
        target: hostTarget,
        sync: host,
        authorizePlayback: () async => true,
      )..start();
      final guestBridge = PlaybackSyncBridge(
        target: guestTarget,
        sync: guest,
        authorizePlayback: () async => true,
      )..start();
      addTearDown(() async {
        await hostBridge.dispose();
        await guestBridge.dispose();
        await host.dispose();
        await guest.dispose();
        await hostTarget.close();
        await guestTarget.close();
        await server.close();
      });

      await server.dial(host, name: 'host');
      await server.dial(guest, name: 'guest');
      await hostBridge.load(_movie);
      await guestBridge.load(_movie);
      await _until(
        () =>
            server.hasAnnouncedFile('host') && server.hasAnnouncedFile('guest'),
      );

      expect(await hostBridge.play(), isTrue);
      server.sendHeartbeat();
      await _until(() => !server.roomPaused && guestTarget.snapshot.buffering);
      await _until(() {
        server.sendHeartbeat();
        return server.reportedPaused('guest') == false;
      });
      expect(server.roomSetBy, 'host');
      expect(server.acceptedChanges.single.by, 'host');

      // The guest has accepted Play but its native decoder has not advanced.
      // Its ordinary heartbeat is a valid candidate for upstream's slowest-
      // watcher room anchor; no guest seek or pause command is involved.
      _emit(hostTarget, const Duration(seconds: 8), playing: true);
      server.sendHeartbeat();
      await _until(
        () => server.reportedPosition('host') == const Duration(seconds: 8),
      );
      final pendingRewind = Completer<void>();
      hostTarget.seekGate = pendingRewind;
      hostTarget.bufferAfterRewind = true;
      roomClock = roomClock.add(const Duration(seconds: 2));
      server.sendHeartbeat();
      await _until(() => server.roomSetBy == 'guest');
      await _until(
        () => hostTarget.commands.any((command) => command.startsWith('seek:')),
      );

      expect(server.roomPosition, lessThan(const Duration(seconds: 4)));
      expect(
        hostTarget.commands.where((command) => command == 'play').length,
        1,
        reason: 'the remote rewind must finish before its Play resumes',
      );
      expect(server.acceptedChanges.length, 1);
      expect(_guestSignalledChanges(guest), isEmpty);
      expect(hostTarget.snapshot.playing, isFalse);

      // The follow seek can finish much later than the room update. Its Play
      // then resumes through a buffering interval without creating a user seek
      // or a room-wide pause.
      pendingRewind.complete();
      await _until(() => hostTarget.snapshot.buffering);
      expect(
        hostTarget.commands.where((command) => command == 'play').length,
        2,
      );
      expect(hostBridge.playRequested, isTrue);
      expect(server.roomPaused, isFalse);
      expect(server.acceptedChanges.length, 1);

      // The native decoder moves only a little after the remote rewind, then
      // spends the rest of this interval buffering. A fresh room heartbeat now
      // puts it more than 750 ms behind, even though this was not its first Play.
      final rewind = Duration(
        milliseconds: int.parse(
          hostTarget.commands
              .firstWhere((command) => command.startsWith('seek:'))
              .substring(5),
        ),
      );
      roomClock = roomClock.add(const Duration(milliseconds: 950));
      server.sendHeartbeat();
      await _until(
        () =>
            (host.lastObservedRoomState?.position ?? Duration.zero) >
            rewind + const Duration(milliseconds: 850),
        description: 'fresh room heartbeat after the delayed rewind',
      );
      final nativeRecovery = rewind + const Duration(milliseconds: 100);
      expect(
        host.lastObservedRoomState!.position - nativeRecovery,
        greaterThan(const Duration(milliseconds: 750)),
      );
      _emit(hostTarget, nativeRecovery, playing: true);
      _emit(guestTarget, const Duration(milliseconds: 500), playing: true);
      await _until(() {
        server.sendHeartbeat();
        return (server.reportedPosition('host') ?? Duration.zero) >=
                nativeRecovery &&
            (server.reportedPosition('guest') ?? Duration.zero) >=
                const Duration(milliseconds: 500);
      });
      await _until(
        () =>
            hostTarget.commands
                .where((command) => command.startsWith('seek:'))
                .length >=
            2,
        description: 'native catch-up seek after a buffered remote rewind',
      );
      expect(hostTarget.snapshot.playing, isTrue);
      expect(guestTarget.snapshot.playing, isTrue);
      expect(server.roomPaused, isFalse);
      expect(_guestSignalledChanges(guest), isEmpty);
    },
  );
}

List<Map> _guestSignalledChanges(SyncplayClient guest) => guest
    .debugSentMessages
    .where((message) => message['State'] is Map)
    .map((message) => message['State'] as Map)
    .where(
      (state) =>
          (state['playstate'] is Map &&
              (state['playstate'] as Map)['doSeek'] == true) ||
          (state['ignoringOnTheFly'] is Map &&
              (state['ignoringOnTheFly'] as Map)['client'] != null),
    )
    .toList();

void _emit(SyncTestTarget target, Duration position, {required bool playing}) {
  final state = target.snapshot;
  target.emit(
    PlaybackSnapshot(
      media: state.media,
      position: position,
      duration: state.duration,
      playing: playing,
      connection: state.connection,
    ),
  );
}

Future<void> _until(
  bool Function() condition, {
  String description = 'protocol condition',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('$description not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _BufferOnFirstPlayTarget extends SyncTestTarget {
  @override
  Future<void> play() async {
    await super.play();
    final state = snapshot;
    emit(
      PlaybackSnapshot(
        media: state.media,
        position: state.position,
        duration: state.duration,
        buffering: true,
        connection: state.connection,
      ),
    );
  }
}

class _BufferAfterRewindTarget extends SyncTestTarget {
  bool bufferAfterRewind = false;

  @override
  Future<void> play() async {
    await super.play();
    if (!bufferAfterRewind) return;
    final state = snapshot;
    emit(
      PlaybackSnapshot(
        media: state.media,
        position: state.position,
        duration: state.duration,
        buffering: true,
        connection: state.connection,
      ),
    );
  }
}
