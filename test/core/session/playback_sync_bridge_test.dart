import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/sync_playback_fakes.dart';
import '../../support/syncplay_room_server.dart';

final movie = MediaItem(
  uri: Uri.parse('https://example.com/movie.mp4'),
  title: 'Movie',
);
final second = MediaItem(
  uri: Uri.parse('https://example.com/second.mp4'),
  title: 'Second',
);
const remotePlay = PeerPlayState(
  position: Duration(seconds: 45),
  paused: false,
  setBy: 'peer',
);

void main() {
  late SyncTestCore sync;
  late SyncTestTarget target;
  late PlaybackSyncBridge bridge;
  late List<Object> errors;
  Future<bool> Function() authorize = () async => true;
  setUp(() {
    sync = SyncTestCore();
    target = SyncTestTarget();
    errors = [];
    authorize = () async => true;
    bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () => authorize(),
      onError: errors.add,
    );
    bridge.start();
  });
  tearDown(() async {
    await bridge.dispose();
    await sync.dispose();
    await target.close();
  });

  test(
    'unconfirmed native open never publishes; local adoption asserts current time',
    () async {
      await target.load(movie, position: const Duration(seconds: 22));
      expect(sync.published, isEmpty);
      await bridge.adoptOpenSource(movie.uri.toString());
      expect(sync.published.last.position.inSeconds, 22);
      expect(sync.changes, [true]);
    },
  );

  test(
    'slow load adopts newest room time and never echoes peer intent',
    () async {
      final gate = Completer<void>();
      target.loadGate = gate;
      final loading = bridge.load(movie);
      sync.peer(remotePlay);
      expect(sync.published.last.position.inSeconds, 45);
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 49),
        paused: false,
        setBy: 'peer',
      );
      gate.complete();
      await loading;
      expect(target.snapshot.position.inSeconds, 49);
      expect(target.snapshot.playing, isTrue);
      expect(sync.changes, isEmpty);
    },
  );

  test(
    'superseded load cannot confirm or publish the rejected source',
    () async {
      final gate = Completer<void>();
      target.loadGate = gate;
      final old = bridge.load(movie);
      await bridge.load(second, position: const Duration(seconds: 8));
      gate.complete();
      await old;
      expect(target.snapshot.media, second);
      expect(sync.published.every((s) => s.position.inSeconds == 8), isTrue);
    },
  );

  test('pending remote seek cannot play after a newer pause', () async {
    await bridge.load(movie);
    final gate = Completer<void>();
    target.seekGate = gate;
    sync.peer(remotePlay);
    await until(() => target.commands.contains('seek:45000'));
    sync.peer(
      const PeerPlayState(
        position: Duration(seconds: 12),
        paused: true,
        setBy: 'peer',
      ),
    );
    expect(sync.published.last.position.inSeconds, 12);
    gate.complete();
    await until(() => target.snapshot.position.inSeconds == 12);
    expect(target.commands, isNot(contains('play')));
    expect(sync.changes, isEmpty);
  });

  test('source change invalidates in-flight peer commands', () async {
    await bridge.load(movie);
    final gate = Completer<void>();
    target.seekGate = gate;
    sync.peer(remotePlay);
    await until(() => target.commands.contains('seek:45000'));
    bridge.beginSourceLoad();
    await target.load(second);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(target.commands, isNot(contains('play')));
    expect(target.snapshot.media, second);
  });

  test('denied remote play stays paused and publishes the refusal', () async {
    await bridge.load(movie);
    authorize = () async => false;
    sync.peer(remotePlay);
    await until(() => sync.changes.isNotEmpty);
    expect(target.snapshot.playing, isFalse);
    expect(sync.published.last.paused, isTrue);
  });

  test(
    'user pause cancels pending authorization without waiting for a paywall',
    () async {
      await bridge.load(movie);
      final permission = Completer<bool>();
      authorize = () => permission.future;
      final play = bridge.play();
      await Future<void>.delayed(Duration.zero);
      await bridge.pause().timeout(const Duration(seconds: 1));
      expect(await play, isFalse);
      permission.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(target.commands, isNot(contains('play')));
    },
  );

  test(
    'native command failure surfaces and does not poison next peer command',
    () async {
      await bridge.load(movie);
      target.throwSeek = true;
      sync.peer(remotePlay);
      await until(() => errors.isNotEmpty);
      target.throwSeek = false;
      sync.peer(
        const PeerPlayState(
          position: Duration(seconds: 8),
          paused: true,
          setBy: 'peer',
        ),
      );
      await until(() => target.snapshot.position.inSeconds == 8);
      expect(target.snapshot.playing, isFalse);
    },
  );

  test(
    'losing an established connection pauses; recovery does not resume',
    () async {
      await bridge.load(movie);
      sync.connection(SyncConnectionStatus.connected);
      await bridge.play();
      sync.connection(SyncConnectionStatus.reconnecting);
      await until(() => !target.snapshot.playing);
      sync.connection(SyncConnectionStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(target.snapshot.playing, isFalse);
    },
  );

  test(
    'two real clients drive two targets through bridge commands in both directions',
    () async {
      final server = await SyncplayRoomServer.start();
      final a = SyncplayClient();
      final b = SyncplayClient();
      final firstTarget = SyncTestTarget();
      final secondTarget = SyncTestTarget();
      final firstBridge = PlaybackSyncBridge(
        target: firstTarget,
        sync: a,
        authorizePlayback: () async => true,
      )..start();
      final secondBridge = PlaybackSyncBridge(
        target: secondTarget,
        sync: b,
        authorizePlayback: () async => true,
      )..start();
      addTearDown(() async {
        await firstBridge.dispose();
        await secondBridge.dispose();
        await a.dispose();
        await b.dispose();
        await firstTarget.close();
        await secondTarget.close();
        await server.close();
      });
      await server.dial(a, name: 'alice');
      await server.dial(b, name: 'bob');
      await firstBridge.load(movie);
      await secondBridge.load(movie);
      await firstBridge.seek(const Duration(seconds: 31));
      await firstBridge.play();
      await until(
        () =>
            secondTarget.snapshot.playing &&
            secondTarget.snapshot.position.inSeconds >= 31,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await secondBridge.pause();
      await secondBridge.seek(const Duration(seconds: 66));
      await until(
        () =>
            !firstTarget.snapshot.playing &&
            firstTarget.snapshot.position.inSeconds == 66,
      );
      expect(server.roomSetBy, 'bob');
    },
  );
}

Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
