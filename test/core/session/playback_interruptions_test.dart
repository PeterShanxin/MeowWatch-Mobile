import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/sync_playback_fakes.dart';
import '../../support/syncplay_room_server.dart';

void main() {
  test('focus cancels Play while adopting a playing Local source', () async {
    final target = _FocusRetainingTarget();
    final sync = SyncTestCore();
    final movie = MediaItem(
      uri: Uri.parse('https://example.com/adopted.mp4'),
      title: 'Adopted',
    );
    await target.load(movie);
    await target.play();
    final bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () async => true,
    )..start();
    addTearDown(() async {
      await bridge.dispose();
      await target.close();
      await sync.dispose();
    });
    sync.connection(SyncConnectionStatus.connected);
    final gate = Completer<void>();
    final entered = Completer<void>();
    target.playGate = gate;
    target.playEntered = entered;
    final adopting = bridge.adoptOpenSource(movie.uri.toString());
    await entered.future;
    target.interruptFocus();
    expect(bridge.playRequested, isFalse);
    expect(sync.published.last.paused, isTrue);
    gate.complete();
    await adopting;
    await _until(
      () => target.commands.last == 'pause' && !target.snapshot.playing,
      onTimeout: () => 'Adopted pending Play was not re-paused',
    );
    expect(bridge.playRequested, isFalse);
    expect(sync.published.every((state) => state.paused), isTrue);
  });

  test(
    'focus supersedes an in-flight local Play before it is announced',
    () async {
      final target = _FocusRetainingTarget();
      final sync = SyncTestCore();
      final bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      addTearDown(() async {
        await bridge.dispose();
        await target.close();
        await sync.dispose();
      });
      await bridge.load(
        MediaItem(
          uri: Uri.parse('https://example.com/pending.mp4'),
          title: 'Pending',
        ),
      );
      sync.connection(SyncConnectionStatus.connected);
      final gate = Completer<void>();
      final entered = Completer<void>();
      target.playGate = gate;
      target.playEntered = entered;
      final playing = bridge.play();
      await entered.future;
      target.interruptFocus();
      expect(bridge.playRequested, isFalse);
      gate.complete();
      expect(await playing, isFalse);
      await _until(
        () => target.commands.isNotEmpty && target.commands.last == 'pause',
        onTimeout: () =>
            'Interrupted Play was not re-paused: ${target.commands}',
      );
      expect(target.snapshot.playing, isFalse);
      expect(sync.changes, isEmpty);
      expect(sync.published.last.paused, isTrue);

      expect(await bridge.play(), isTrue);
      expect(target.snapshot.playing, isTrue);
      expect(sync.changes, [false]);
    },
  );

  test(
    'focus during an explicit Pause does not publish a second Pause',
    () async {
      final target = _FocusRetainingTarget();
      final sync = SyncTestCore();
      final bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      addTearDown(() async {
        await bridge.dispose();
        await target.close();
        await sync.dispose();
      });
      await bridge.load(
        MediaItem(
          uri: Uri.parse('https://example.com/pausing.mp4'),
          title: 'Pausing',
        ),
      );
      sync.connection(SyncConnectionStatus.connected);
      await bridge.play();
      final gate = Completer<void>();
      final entered = Completer<void>();
      target.pauseGate = gate;
      target.pauseEntered = entered;
      final pausing = bridge.pause();
      await entered.future;
      target.interruptFocus();
      expect(sync.changes, [false, false]);
      gate.complete();
      await pausing;
      await _until(
        () =>
            target.commands.where((command) => command == 'pause').length == 2,
        onTimeout: () => 'Interrupted native Pause was not reasserted',
      );
      expect(sync.changes, [false, false]);
      expect(sync.published.last.paused, isTrue);
    },
  );

  test(
    'focus cancels a pending peer Play and ignores a replaced source',
    () async {
      final target = _FocusRetainingTarget();
      final sync = SyncTestCore();
      final bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      addTearDown(() async {
        await bridge.dispose();
        await target.close();
        await sync.dispose();
      });
      final first = MediaItem(
        uri: Uri.parse('https://example.com/remote-pending.mp4'),
        title: 'Remote pending',
      );
      await bridge.load(first);
      sync.connection(SyncConnectionStatus.connected);
      final seekGate = Completer<void>();
      target.seekGate = seekGate;
      sync.peer(
        const PeerPlayState(
          position: Duration(seconds: 8),
          paused: false,
          setBy: 'bob',
        ),
      );
      await _until(
        () => target.commands.any((command) => command.startsWith('seek:')),
        onTimeout: () => 'Peer Play did not reach native seek',
      );
      target.interruptFocus();
      expect(bridge.playRequested, isFalse);
      expect(sync.published.last.paused, isTrue);
      expect(sync.changes, [false]);
      seekGate.complete();
      await _until(
        () => target.commands.last == 'pause',
        onTimeout: () => 'Pending peer Play was not re-paused',
      );
      expect(target.commands.where((command) => command == 'play'), isEmpty);
      expect(sync.changes, [false]);

      bridge.beginSourceLoad();
      target.interruptFocus();
      expect(sync.changes, [false]);
    },
  );

  test('focus supersedes peer Play already inside native play()', () async {
    final target = _FocusRetainingTarget();
    final sync = SyncTestCore();
    final bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () async => true,
    )..start();
    addTearDown(() async {
      await bridge.dispose();
      await target.close();
      await sync.dispose();
    });
    await bridge.load(
      MediaItem(
        uri: Uri.parse('https://example.com/native-pending.mp4'),
        title: 'Native pending',
      ),
    );
    sync.connection(SyncConnectionStatus.connected);
    final playGate = Completer<void>();
    final entered = Completer<void>();
    target.playGate = playGate;
    target.playEntered = entered;
    sync.peer(
      const PeerPlayState(position: Duration.zero, paused: false, setBy: 'bob'),
    );
    await entered.future;
    target.interruptFocus();
    expect(bridge.playRequested, isFalse);
    expect(sync.changes, [false]);
    playGate.complete();
    await _until(
      () => target.commands.isNotEmpty && target.commands.last == 'pause',
      onTimeout: () => 'Pending native Play survived focus interruption',
    );
    expect(target.snapshot.playing, isFalse);
    expect(sync.published.last.paused, isTrue);
    expect(sync.changes, [false]);
  });

  test('focus pauses a disconnected decoder without a room change', () async {
    final target = _FocusRetainingTarget();
    final sync = SyncTestCore();
    final bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () async => true,
    )..start();
    addTearDown(() async {
      await bridge.dispose();
      await target.close();
      await sync.dispose();
    });
    await bridge.load(
      MediaItem(
        uri: Uri.parse('https://example.com/disconnected.mp4'),
        title: 'Disconnected',
      ),
    );
    await bridge.play();
    final changesBefore = sync.changes.length;
    target.interruptFocus();
    await _until(
      () => target.commands.last == 'pause',
      onTimeout: () => 'Disconnected decoder was not paused',
    );
    expect(bridge.playRequested, isFalse);
    expect(sync.changes.length, changesBefore);
  });

  test('Together publishes one focus Pause while native is buffering', () async {
    final server = await SyncplayRoomServer.start();
    final interruptedClient = SyncplayClient();
    final peerClient = SyncplayClient();
    final interruptedTarget = _FocusRetainingTarget();
    final peerTarget = SyncTestTarget();
    final interruptedBridge = PlaybackSyncBridge(
      target: interruptedTarget,
      sync: interruptedClient,
      authorizePlayback: () async => true,
    )..start();
    final peerBridge = PlaybackSyncBridge(
      target: peerTarget,
      sync: peerClient,
      authorizePlayback: () async => true,
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
      uri: Uri.parse('https://example.com/focus-buffering.mp4'),
      title: 'Focus buffering',
    );
    await interruptedBridge.load(movie);
    await peerBridge.load(movie);
    await peerBridge.play();
    await _until(
      () =>
          !server.roomPaused &&
          interruptedTarget.snapshot.playing &&
          peerTarget.snapshot.playing,
      onTimeout: () => 'Room never started both players',
    );
    final changesBefore = server.acceptedChanges.length;
    final pausesBefore = interruptedTarget.commands
        .where((command) => command == 'pause')
        .length;

    // A regular buffering snapshot carries no new room intent.
    _emitNative(interruptedTarget, playing: false, buffering: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.roomPaused, isFalse);
    expect(server.acceptedChanges.length, changesBefore);

    // Native focus loss has a separate signal even if there is never another
    // non-buffering playback snapshot after the loss.
    interruptedTarget.interruptFocus();
    expect(interruptedBridge.playRequested, isFalse);
    await _until(
      () =>
          server.roomPaused &&
          server.roomSetBy == 'alice' &&
          !peerTarget.snapshot.playing &&
          !interruptedTarget.retainedPlayRequest,
      onTimeout: () =>
          'Focus pause missing: roomPaused=${server.roomPaused}, '
          'setBy=${server.roomSetBy}, changes=${server.acceptedChanges.length}',
    );
    final focusChanges = server.acceptedChanges.skip(changesBefore).toList();
    expect(focusChanges, hasLength(1));
    expect(focusChanges.single.paused, isTrue);
    expect(focusChanges.single.doSeek, isFalse);
    expect(
      interruptedTarget.commands.where((command) => command == 'pause').length,
      pausesBefore + 1,
    );

    interruptedTarget.interruptFocus();
    interruptedTarget.releaseFocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.acceptedChanges.length, changesBefore + 1);
    expect(interruptedTarget.focusReleasePlayEvents, 0);

    await interruptedBridge.play();
    await _until(
      () =>
          !server.roomPaused &&
          interruptedTarget.snapshot.playing &&
          peerTarget.snapshot.playing,
      onTimeout: () => 'Explicit Play did not resume the room',
    );
  });

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

class _FocusRetainingTarget extends SyncTestTarget
    implements PlaybackInterruptionTarget {
  bool retainedPlayRequest = false;
  int focusReleasePlayEvents = 0;
  final _focusEvents = StreamController<int>.broadcast(sync: true);
  final _focusOwners = <Object>{};
  int _focusVersion = 0;
  Completer<void>? playGate;
  Completer<void>? playEntered;
  Completer<void>? pauseGate;
  Completer<void>? pauseEntered;

  @override
  Stream<int> get focusInterruptions => _focusEvents.stream;

  @override
  Future<void> requireExplicitResume(Object owner) async {
    _focusOwners.add(owner);
  }

  @override
  Future<void> releaseExplicitResume(Object owner) async {
    _focusOwners.remove(owner);
  }

  void interruptFocus() {
    if (_focusOwners.isNotEmpty) _focusEvents.add(++_focusVersion);
  }

  @override
  Future<void> play() async {
    retainedPlayRequest = true;
    playEntered?.complete();
    playEntered = null;
    final gate = playGate;
    playGate = null;
    await gate?.future;
    await super.play();
  }

  @override
  Future<void> pause() async {
    pauseEntered?.complete();
    pauseEntered = null;
    final gate = pauseGate;
    pauseGate = null;
    await gate?.future;
    retainedPlayRequest = false;
    await super.pause();
  }

  void loseFocus() => _emitNative(this, playing: false);

  void releaseFocus() {
    if (!retainedPlayRequest) return;
    focusReleasePlayEvents++;
    _emitNative(this, playing: true);
  }

  @override
  Future<void> close() async {
    await _focusEvents.close();
    await super.close();
  }
}

void _emitNative(
  SyncTestTarget target, {
  required bool playing,
  bool buffering = false,
}) {
  final current = target.snapshot;
  target.emit(
    PlaybackSnapshot(
      media: current.media,
      position: current.position,
      duration: current.duration,
      playing: playing,
      buffering: buffering,
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
