import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/sync_playback_fakes.dart';
import '../../support/syncplay_room_server.dart';

void main() {
  for (final early in [false, true]) {
    test(
      early
          ? 'Together reconciles an early native pause with no later event and accepts explicit Play'
          : 'Together pauses the room on a settled native interruption and waits for explicit Play',
      () async {
        final server = await SyncplayRoomServer.start();
        final interruptedClient = SyncplayClient();
        final peerClient = SyncplayClient();
        final interruptedTarget = _FocusRetainingTarget();
        final peerTarget = SyncTestTarget();
        final settleWindow = early
            ? const Duration(seconds: 1)
            : const Duration(milliseconds: 30);
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
        Future<void> untilPhase(
          String phase,
          bool Function() condition,
        ) => _until(
          condition,
          onTimeout: () =>
              '$phase: roomPaused=${server.roomPaused}, '
              'setBy=${server.roomSetBy}, '
              'aliceReported=${server.reportedPaused('alice')}, '
              'bobReported=${server.reportedPaused('bob')}, '
              'aliceNative=${interruptedTarget.snapshot.playing}, '
              'bobNative=${peerTarget.snapshot.playing}, '
              'aliceRequested=${interruptedBridge.playRequested}, '
              'bobRequested=${peerBridge.playRequested}, '
              'changeCount=${server.acceptedChanges.length}, '
              'lastChange=${server.acceptedChanges.isEmpty ? null : server.acceptedChanges.last}',
        );
        if (early) {
          await peerBridge.play();
        } else {
          await interruptedBridge.play();
        }
        await untilPhase(
          'initial Play',
          () =>
              !server.roomPaused &&
              interruptedTarget.snapshot.playing &&
              peerTarget.snapshot.playing &&
              server.reportedPaused('alice') == false &&
              server.reportedPaused('bob') == false,
        );
        if (!early) await Future<void>.delayed(settleWindow * 2);
        final beforeInterruption = server.acceptedChanges.length;
        final pausesBeforeInterruption = interruptedTarget.commands
            .where((command) => command == 'pause')
            .length;
        expect(interruptedTarget.retainedPlayRequest, isTrue);

        // A transient focus loss pauses isPlaying but retains playWhenReady.
        // Without an explicit pause(), releasing focus emits native Play.
        interruptedTarget.loseFocus();
        if (early) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(server.acceptedChanges.length, beforeInterruption);
          expect(interruptedTarget.snapshot.playing, isFalse);
        }
        await untilPhase(
          'native pause',
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

        await untilPhase(
          'retained native request cleared',
          () =>
              !interruptedTarget.retainedPlayRequest &&
              interruptedTarget.commands
                      .where((command) => command == 'pause')
                      .length ==
                  pausesBeforeInterruption + 1,
        );
        interruptedTarget.releaseFocus();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(interruptedTarget.focusReleasePlayEvents, 0);
        expect(interruptedTarget.snapshot.playing, isFalse);
        expect(server.roomPaused, isTrue);
        expect(peerTarget.snapshot.playing, isFalse);
        expect(server.acceptedChanges.length, beforeInterruption + 1);

        await interruptedBridge.play();
        await untilPhase(
          'explicit Play',
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
}

class _FocusRetainingTarget extends SyncTestTarget {
  bool retainedPlayRequest = false;
  int focusReleasePlayEvents = 0;

  @override
  Future<void> play() async {
    retainedPlayRequest = true;
    await super.play();
  }

  @override
  Future<void> pause() async {
    retainedPlayRequest = false;
    await super.pause();
  }

  void loseFocus() => _emitNative(this, playing: false);

  void releaseFocus() {
    if (!retainedPlayRequest) return;
    focusReleasePlayEvents++;
    _emitNative(this, playing: true);
  }
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

Future<void> _until(
  bool Function() condition, {
  required String Function() onTimeout,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(onTimeout());
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
