import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/sync_playback_fakes.dart';
import '../../support/syncplay_room_server.dart';

void main() {
  test(
    'Together pauses the room on a settled native interruption and waits for explicit Play',
    () async {
      final server = await SyncplayRoomServer.start();
      final interruptedClient = SyncplayClient();
      final peerClient = SyncplayClient();
      final interruptedTarget = SyncTestTarget();
      final peerTarget = SyncTestTarget();
      const settleWindow = Duration(milliseconds: 30);
      final interruptedBridge = PlaybackSyncBridge(
        target: interruptedTarget,
        sync: interruptedClient,
        authorizePlayback: () async => true,
        settleWindow: settleWindow,
      )..start();
      final peerBridge = PlaybackSyncBridge(
        target: peerTarget,
        sync: peerClient,
        authorizePlayback: () async => true,
        settleWindow: settleWindow,
      )..start();
      addTearDown(() async {
        await interruptedBridge.dispose();
        await peerBridge.dispose();
        await interruptedClient.dispose();
        await peerClient.dispose();
        await interruptedTarget.close();
        await peerTarget.close();
        await server.close();
      });

      await server.dial(interruptedClient, name: 'alice');
      await server.dial(peerClient, name: 'bob');
      final movie = MediaItem(
        uri: Uri.parse('https://example.com/movie.mp4'),
        title: 'Movie',
      );
      await interruptedBridge.load(movie);
      await peerBridge.load(movie);
      await interruptedBridge.play();
      await _until(
        () =>
            !server.roomPaused &&
            interruptedTarget.snapshot.playing &&
            peerTarget.snapshot.playing &&
            server.reportedPaused('alice') == false &&
            server.reportedPaused('bob') == false,
      );
      await Future<void>.delayed(settleWindow * 2);
      final beforeInterruption = server.acceptedChanges.length;

      // Model the non-buffering, ready player callback after Android has taken
      // audio focus. This is a socket/bridge regression, not an Android gate.
      _emitNative(interruptedTarget, playing: false);
      await _until(
        () =>
            server.roomPaused &&
            server.roomSetBy == 'alice' &&
            !peerTarget.snapshot.playing &&
            server.reportedPaused('alice') == true &&
            server.reportedPaused('bob') == true,
      );
      final interruptionChanges = server.acceptedChanges.skip(
        beforeInterruption,
      );
      expect(interruptionChanges, hasLength(1));
      expect(interruptionChanges.single.paused, isTrue);
      expect(interruptionChanges.single.doSeek, isFalse);
      expect(server.reportedPaused('alice'), isTrue);
      expect(server.reportedPaused('bob'), isTrue);

      // A native auto-resume after focus release is an echo, not room intent.
      final pausesBeforeEcho = interruptedTarget.commands
          .where((command) => command == 'pause')
          .length;
      _emitNative(interruptedTarget, playing: true);
      await _until(
        () =>
            !interruptedTarget.snapshot.playing &&
            interruptedTarget.commands
                    .where((command) => command == 'pause')
                    .length ==
                pausesBeforeEcho + 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.roomPaused, isTrue);
      expect(peerTarget.snapshot.playing, isFalse);
      expect(server.acceptedChanges.length, beforeInterruption + 1);

      await interruptedBridge.play();
      await _until(
        () =>
            !server.roomPaused &&
            interruptedTarget.snapshot.playing &&
            peerTarget.snapshot.playing &&
            server.reportedPaused('alice') == false &&
            server.reportedPaused('bob') == false,
      );
      expect(server.roomSetBy, 'alice');
      expect(server.acceptedChanges.last.paused, isFalse);
      expect(server.acceptedChanges.last.doSeek, isFalse);
    },
  );
}

void _emitNative(SyncTestTarget target, {required bool playing}) {
  final current = target.snapshot;
  target.emit(
    PlaybackSnapshot(
      media: current.media,
      position: current.position,
      duration: current.duration,
      playing: playing,
      buffering: false,
      connection: PlaybackConnection.ready,
    ),
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Together interruption state was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
