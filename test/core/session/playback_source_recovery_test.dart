import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';

import '../../support/sync_playback_fakes.dart';

final _movie = MediaItem(
  uri: Uri.parse('https://example.com/movie.mp4'),
  title: 'Movie',
);
const _play = PeerPlayState(
  position: Duration(seconds: 32),
  paused: false,
  setBy: 'peer',
);
const _pause = PeerPlayState(
  position: Duration(seconds: 22),
  paused: true,
  setBy: 'peer',
);

void main() {
  late SyncTestCore sync;
  late _RecoverableTarget target;
  late PlaybackSyncBridge bridge;
  late List<Object> errors;
  var authorizations = 0;
  var allowed = true;

  setUp(() {
    sync = SyncTestCore();
    target = _RecoverableTarget();
    errors = [];
    authorizations = 0;
    allowed = true;
    bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () async {
        authorizations++;
        return allowed;
      },
      onError: errors.add,
    )..start();
  });
  tearDown(() async {
    await bridge.dispose();
    await sync.dispose();
    await target.close();
  });

  Future<void> connect(SyncConnectionStatus status) async {
    sync.connection(status);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> open({MediaItem? media}) async {
    await connect(SyncConnectionStatus.connected);
    await bridge.load(media ?? _movie, position: _pause.position);
  }

  Future<void> lose() => connect(SyncConnectionStatus.reconnecting);
  Future<void> reconnect() => connect(SyncConnectionStatus.connected);

  test(
    'failed network source reopens paused and rejects stale room Play',
    () async {
      await open();
      sync.lastObservedRoomState = _play;
      await lose();
      target.fail();
      final changes = sync.changes.length;
      await reconnect();
      await _until(() => target.loads.length == 2 && target.snapshot.ready);
      expect(target.loads.last.position, _pause.position);
      expect(target.snapshot.media, _movie);
      expect(target.snapshot.playing, isFalse);
      expect(sync.published.last.paused, isTrue);
      expect(sync.changes.length, changes);
      expect(authorizations, 0);
      sync.peer(_play);
      await Future<void>.delayed(Duration.zero);
      expect(target.commands, isNot(contains('play')));
      expect(sync.published.last.paused, isTrue);

      // A paused heartbeat need not produce a FOLLOW command. It still provides
      // the fresh baseline needed to accept the user's subsequent room Play.
      sync.lastObservedRoomState = _pause;
      sync.peer(_play);
      await _until(() => target.snapshot.playing);
      expect(authorizations, 1);
      expect(target.snapshot.position, _play.position);
      expect(sync.changes.length, changes);
    },
  );

  test(
    'a native failure delivered after TLS rejoin also recovers once',
    () async {
      await open();
      await lose();
      await reconnect();
      expect(target.loads.length, 1);
      if (scenario == 'healthy') {
        sync.peer(_play);
        await Future<void>.delayed(Duration.zero);
        expect(target.snapshot.playing, isFalse);
        expect(authorizations, 0);
      }
      target.fail();
      await _until(() => target.loads.length == 2 && target.snapshot.ready);
      expect(target.snapshot.playing, isFalse);
      target.fail();
      await Future<void>.delayed(Duration.zero);
      expect(target.loads.length, 2);
    },
  );

  test('fresh peer Play during rebuilding follows once after ready', () async {
    await open();
    await lose();
    target.fail();
    final gate = Completer<void>();
    target.loadGate = gate;
    await reconnect();
    sync.lastObservedRoomState = _pause;
    sync.peer(_play);
    expect(target.snapshot.connection, PlaybackConnection.loading);
    expect(authorizations, 0);
    expect(sync.published.last.paused, isTrue);
    gate.complete();
    await _until(() => target.snapshot.playing);
    expect(target.commands.where((c) => c == 'play').length, 1);
    expect(authorizations, 1);
    expect(target.snapshot.position, _play.position);
  });

  test('a later paused heartbeat cancels pending recovery Play', () async {
    await open();
    await lose();
    target.fail();
    final gate = Completer<void>();
    target.loadGate = gate;
    await reconnect();
    sync.lastObservedRoomState = _pause;
    sync.peer(_play);
    sync.lastObservedRoomState = _pause;
    gate.complete();
    await _until(() => target.snapshot.ready);
    expect(target.snapshot.playing, isFalse);
    expect(authorizations, 0);
  });

  test(
    'reconnection during rebuilding discards the former connection Play',
    () async {
      await open();
      await lose();
      target.fail();
      final gate = Completer<void>();
      target.loadGate = gate;
      await reconnect();
      sync.lastObservedRoomState = _pause;
      sync.peer(_play);
      await lose();
      gate.complete();
      await _until(() => target.snapshot.ready);
      await reconnect();
      sync.peer(_play);
      await Future<void>.delayed(Duration.zero);
      expect(target.snapshot.playing, isFalse);
      expect(authorizations, 0);
      expect(target.loads.length, 2);
    },
  );

  test(
    'a second outage that breaks rebuilding gets one new paused attempt',
    () async {
      await open();
      await lose();
      target.fail();
      final gate = Completer<void>();
      target.loadGate = gate;
      target.failNextLoad = true;
      await reconnect();
      sync.lastObservedRoomState = _pause;
      sync.peer(_play);
      await lose();
      await reconnect();
      expect(target.loads.length, 2);
      gate.complete();
      await _until(() => target.loads.length == 3 && target.snapshot.ready);
      expect(target.snapshot.position, _pause.position);
      expect(target.snapshot.playing, isFalse);
      expect(authorizations, 0);
      expect(target.commands, isNot(contains('play')));
      target.fail();
      await reconnect();
      expect(target.loads.length, 3);
    },
  );

  test('fresh recovery Play still obeys host authorization', () async {
    await open();
    await lose();
    target.fail();
    final gate = Completer<void>();
    target.loadGate = gate;
    await reconnect();
    allowed = false;
    sync.lastObservedRoomState = _pause;
    sync.peer(_play);
    gate.complete();
    await _until(() => authorizations == 1);
    await Future<void>.delayed(Duration.zero);
    expect(target.snapshot.playing, isFalse);
    expect(sync.published.last.paused, isTrue);
  });

  test('manual source replacement invalidates the former recovery', () async {
    await open();
    await lose();
    target.fail();
    final gate = Completer<void>();
    target.loadGate = gate;
    await reconnect();
    final second = MediaItem(
      uri: Uri.parse('file:///second.mp4'),
      title: 'Second',
    );
    await bridge.load(second, position: const Duration(seconds: 8));
    final published = sync.published.length;
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(target.snapshot.media, second);
    expect(sync.published.length, published);
    expect(target.commands, isNot(contains('play')));
  });

  test(
    'disposing the bridge prevents a pending recovery publishing or playing',
    () async {
      await open();
      await lose();
      target.fail();
      final gate = Completer<void>();
      target.loadGate = gate;
      await reconnect();
      sync.lastObservedRoomState = _pause;
      sync.peer(_play);
      await bridge.dispose();
      final published = sync.published.length;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sync.published.length, published);
      expect(target.commands, isNot(contains('play')));
    },
  );

  test(
    'failed reopening reports once, keeps position, and allows manual load',
    () async {
      await open();
      await lose();
      target.fail();
      target.failNextLoad = true;
      await reconnect();
      await _until(() => errors.isNotEmpty);
      expect(target.snapshot.connection, PlaybackConnection.failed);
      expect(target.snapshot.position, _pause.position);
      target.fail();
      await reconnect();
      expect(target.loads.length, 2);
      expect(errors.length, 1);
      await bridge.load(_movie, position: target.snapshot.position);
      expect(target.loads.length, 3);
      expect(target.snapshot.ready, isTrue);
    },
  );

  test(
    'explicit local Play after recovery needs no remote pause baseline',
    () async {
      await open();
      await lose();
      target.fail();
      await reconnect();
      await _until(() => target.loads.length == 2 && target.snapshot.ready);
      expect(await bridge.play(), isTrue);
      expect(authorizations, 1);
    },
  );

  for (final scenario in [
    'healthy',
    'file',
    'receiver',
    'first-load',
    'no-loss',
  ]) {
    test('$scenario does not trigger automatic media reload', () async {
      if (scenario == 'receiver') target.allowRecovery = false;
      if (scenario == 'first-load') {
        await connect(SyncConnectionStatus.connected);
        await target.load(_movie);
      } else {
        await open(
          media: scenario == 'file'
              ? MediaItem(uri: Uri.parse('file:///movie.mp4'), title: 'File')
              : null,
        );
      }
      if (scenario != 'no-loss') await lose();
      if (scenario != 'healthy') target.fail();
      await reconnect();
      expect(target.loads.length, 1);
    });
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Playback recovery did not settle.');
}

class _RecoverableTarget extends SyncTestTarget {
  final loads = <({MediaItem media, Duration position})>[];
  bool failNextLoad = false;
  bool allowRecovery = true;
  int _loadGeneration = 0;

  @override
  bool get canReloadAfterConnectionLoss => allowRecovery;

  void fail() => emit(
    PlaybackSnapshot(
      media: snapshot.media,
      position: snapshot.position,
      duration: snapshot.duration,
      connection: PlaybackConnection.failed,
      error: 'Native source failed.',
    ),
  );

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final generation = ++_loadGeneration;
    loads.add((media: media, position: position));
    if (failNextLoad) {
      failNextLoad = false;
      final gate = loadGate;
      loadGate = null;
      emit(
        PlaybackSnapshot(
          media: media,
          position: position,
          duration: snapshot.duration,
          connection: PlaybackConnection.loading,
        ),
      );
      await gate?.future;
      if (generation != _loadGeneration) return;
      fail();
      throw StateError('Native source could not reopen.');
    }
    await super.load(media, position: position);
  }
}
