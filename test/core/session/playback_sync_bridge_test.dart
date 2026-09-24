import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
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

  Future<void> useDelayedPlayTarget() async {
    await bridge.dispose();
    await target.close();
    target = DelayedPlayTarget();
    bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () => authorize(),
      onError: errors.add,
    )..start();
    await bridge.load(movie);
  }

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

  test(
    'first peer Play catches up once after delayed native movement',
    () async {
      await useDelayedPlayTarget();
      sync.peer(remotePlay);
      await until(() => target.commands.contains('play'));
      expect(target.snapshot.playing, isFalse);
      expect(target.commands.where((c) => c.startsWith('seek:')), [
        'seek:45000',
      ]);
      emitNativePosition(target, const Duration(seconds: 45), playing: true);
      expect(target.commands.where((c) => c.startsWith('seek:')), [
        'seek:45000',
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      emitNativePosition(
        target,
        const Duration(milliseconds: 45100),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
      );
      final correctiveSeek = int.parse(target.commands.last.split(':').last);
      expect(correctiveSeek, greaterThanOrEqualTo(46000));
      expect(correctiveSeek, lessThan(48000));
      await until(
        () => sync.published.last.position.inMilliseconds >= correctiveSeek,
      );
      expect(sync.changes, isEmpty);

      emitNativePosition(
        target,
        Duration(milliseconds: correctiveSeek + 100),
        playing: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(target.commands.where((c) => c.startsWith('seek:')).length, 2);
      expect(errors, isEmpty);
    },
  );

  test(
    'startup correction uses a fresh room heartbeat instead of wall time',
    () async {
      await useDelayedPlayTarget();
      sync.peer(remotePlay);
      await until(() => target.commands.contains('play'));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      // The other decoder also stalled; it did not reach 46.2s just because
      // 1.2s passed. Seeking to that stale projection would create new drift.
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(milliseconds: 45150),
        paused: false,
        setBy: 'peer',
      );
      emitNativePosition(
        target,
        const Duration(milliseconds: 45100),
        playing: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(target.commands.where((c) => c.startsWith('seek:')), [
        'seek:45000',
      ]);
      expect(sync.changes, isEmpty);
    },
  );

  test(
    'initially aligned startup still catches up after later buffering',
    () async {
      await useDelayedPlayTarget();
      sync.peer(remotePlay);
      await until(() => target.commands.contains('play'));
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(milliseconds: 45150),
        paused: false,
        setBy: 'peer',
      );
      emitNativePosition(
        target,
        const Duration(milliseconds: 45100),
        playing: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(target.commands.where((c) => c.startsWith('seek:')).length, 1);

      emitNative(target, playing: false, buffering: true);
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(milliseconds: 46700),
        paused: false,
        setBy: 'peer',
      );
      emitNativePosition(
        target,
        const Duration(milliseconds: 45200),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
      );
      expect(
        target.snapshot.position.inMilliseconds,
        greaterThanOrEqualTo(46700),
      );
      expect(target.snapshot.position.inMilliseconds, lessThan(47000));
      expect(sync.changes, isEmpty);
      expect(errors, isEmpty);
    },
  );

  test(
    'startup seek buffering permits only one follow-up correction',
    () async {
      await useDelayedPlayTarget();
      sync.peer(remotePlay);
      await until(() => target.commands.contains('play'));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      emitNativePosition(
        target,
        const Duration(milliseconds: 45100),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
      );
      final first = target.snapshot.position;
      await until(() => sync.published.last.position >= first);
      emitNative(target, playing: false, buffering: true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      sync.lastObservedRoomState = PeerPlayState(
        position: first + const Duration(milliseconds: 1500),
        paused: false,
        setBy: 'peer',
      );
      emitNativePosition(
        target,
        first + const Duration(milliseconds: 100),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 3,
      );
      final second = target.snapshot.position;
      await until(() => sync.published.last.position >= second);
      // Another buffering cycle cannot cause a third automatic correction.
      emitNative(target, playing: false, buffering: true);
      sync.lastObservedRoomState = PeerPlayState(
        position: second + const Duration(seconds: 2),
        paused: false,
        setBy: 'peer',
      );
      emitNativePosition(
        target,
        second + const Duration(milliseconds: 100),
        playing: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(target.commands.where((c) => c.startsWith('seek:')).length, 3);
      expect(sync.changes, isEmpty);
      expect(errors, isEmpty);
    },
  );

  test('peer pause cancels recovery after the first corrective seek', () async {
    await useDelayedPlayTarget();
    sync.peer(remotePlay);
    await until(() => target.commands.contains('play'));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    emitNativePosition(
      target,
      const Duration(milliseconds: 45100),
      playing: true,
    );
    await until(
      () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
    );
    emitNative(target, playing: false, buffering: true);
    sync.peer(
      const PeerPlayState(
        position: Duration(seconds: 12),
        paused: true,
        setBy: 'peer',
      ),
    );
    await until(() => target.snapshot.position == const Duration(seconds: 12));
    emitNativePosition(target, const Duration(seconds: 47), playing: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(target.commands.where((c) => c.startsWith('seek:')).length, 3);
    expect(sync.published.last.paused, isTrue);
    expect(bridge.playRequested, isFalse);
    expect(sync.changes, isEmpty);
  });

  test(
    'source opening into a playing room catches up after native startup',
    () async {
      await bridge.dispose();
      await target.close();
      target = DelayedPlayTarget();
      bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () => authorize(),
        onError: errors.add,
      )..start();
      final loadGate = Completer<void>();
      target.loadGate = loadGate;
      final loading = bridge.load(movie);
      sync.peer(remotePlay);
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 49),
        paused: false,
        setBy: 'peer',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      loadGate.complete();
      await loading;
      expect(target.commands.where((c) => c.startsWith('seek:')), [
        'seek:49000',
      ]);
      expect(target.snapshot.playing, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      emitNativePosition(
        target,
        const Duration(milliseconds: 49100),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
      );
      final correctiveSeek = int.parse(target.commands.last.split(':').last);
      expect(correctiveSeek, greaterThanOrEqualTo(50000));
      expect(correctiveSeek, lessThan(52000));
      expect(sync.changes, isEmpty);
    },
  );

  test(
    'playing local source adopted into room gets one startup correction',
    () async {
      await bridge.dispose();
      await target.close();
      target = HandoffDelayedTarget();
      await target.load(movie);
      await target.play();
      expect(target.snapshot.playing, isTrue);
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 49),
        paused: false,
        setBy: 'peer',
      );
      bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () => authorize(),
        onError: errors.add,
      )..start();
      await bridge.adoptOpenSource(movie.uri.toString());
      expect(target.commands.where((c) => c.startsWith('seek:')), [
        'seek:49000',
      ]);
      expect(target.snapshot.playing, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      emitNativePosition(
        target,
        const Duration(milliseconds: 49100),
        playing: true,
      );
      await until(
        () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
      );
      expect(sync.changes, isEmpty);
    },
  );

  test('new peer pause cancels first Play catch-up', () async {
    await useDelayedPlayTarget();
    sync.peer(remotePlay);
    await until(() => target.commands.contains('play'));
    sync.peer(
      const PeerPlayState(
        position: Duration(seconds: 12),
        paused: true,
        setBy: 'peer',
      ),
    );
    await until(() => target.snapshot.position == const Duration(seconds: 12));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    emitNativePosition(
      target,
      const Duration(milliseconds: 45100),
      playing: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(target.commands.where((c) => c.startsWith('seek:')), [
      'seek:45000',
      'seek:12000',
    ]);
    expect(sync.published.last.paused, isTrue);
    expect(sync.changes, isEmpty);
  });

  test('explicit peer seek does not receive a second startup seek', () async {
    await useDelayedPlayTarget();
    sync.peer(
      const PeerPlayState(
        position: Duration(seconds: 45),
        paused: false,
        doSeek: true,
        setBy: 'peer',
      ),
    );
    await until(() => target.commands.contains('play'));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    emitNativePosition(
      target,
      const Duration(milliseconds: 45100),
      playing: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(target.commands.where((c) => c.startsWith('seek:')), ['seek:45000']);
    expect(sync.changes, isEmpty);
  });

  test('new local pause wins while corrective seek is pending', () async {
    await useDelayedPlayTarget();
    sync.peer(remotePlay);
    await until(() => target.commands.contains('play'));
    final gate = Completer<void>();
    target.seekGate = gate;

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    emitNativePosition(
      target,
      const Duration(milliseconds: 45100),
      playing: true,
    );
    await until(
      () => target.commands.where((c) => c.startsWith('seek:')).length == 2,
    );
    final firstAfterPause = sync.published.length;
    final pause = bridge.pause();
    gate.complete();
    await pause;

    expect(sync.published.skip(firstAfterPause).every((s) => s.paused), isTrue);
    expect(sync.published.last.paused, isTrue);
    expect(sync.changes, [false]);
    expect(errors, isEmpty);
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
    'buffer recovery is bounded and a persistent native pause still publishes',
    () async {
      await bridge.load(movie);
      await bridge.play();
      await bridge.dispose();
      fakeAsync((clock) {
        // Bind the listener in this zone so its recovery timer uses this clock.
        bridge = PlaybackSyncBridge(
          target: target,
          sync: sync,
          authorizePlayback: () async => true,
        )..start();
        unawaited(bridge.markSourceOpen(movie.uri.toString()));
        emitNative(target, playing: false, buffering: true);
        expect(sync.published.last.paused, isFalse);
        emitNative(target, playing: false, buffering: false);
        expect(sync.published.last.paused, isFalse);
        clock.elapse(bridge.settleWindow);
        expect(sync.published.last.paused, isTrue);
        expect(target.commands.where((c) => c == 'play').length, 1);
      });
    },
  );

  test(
    'seek preserves buffer intent and explicit user pause overrides it',
    () async {
      await bridge.load(movie);
      await bridge.play();
      emitNative(target, playing: false, buffering: true);
      await bridge.seek(const Duration(seconds: 20));
      expect(sync.published.last.position.inSeconds, 20);
      expect(sync.published.last.paused, isFalse);
      expect(sync.changes.last, isTrue);
      emitNative(target, playing: false, buffering: true);
      await bridge.pause();
      expect(sync.published.last.paused, isTrue);
      expect(sync.changes.last, isFalse);
    },
  );

  test('source replacement cancels buffer recovery publication', () async {
    await bridge.load(movie);
    await bridge.play();
    await bridge.dispose();
    fakeAsync((clock) {
      bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      unawaited(bridge.markSourceOpen(movie.uri.toString()));
      emitNative(target, playing: false, buffering: true);
      emitNative(target, playing: false, buffering: false);
      final beforeReplacement = sync.published.length;
      bridge.beginSourceLoad();
      clock.elapse(bridge.settleWindow);
      expect(sync.published.length, beforeReplacement);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'early ready native pause publishes after the peer settle window',
    () async {
      await bridge.load(movie);
      await bridge.dispose();
      fakeAsync((clock) {
        bridge = PlaybackSyncBridge(
          target: target,
          sync: sync,
          authorizePlayback: () async => true,
        )..start();
        unawaited(bridge.markSourceOpen(movie.uri.toString()));
        clock.flushMicrotasks();
        sync.peer(remotePlay);
        clock.flushMicrotasks();
        expect(target.snapshot.playing, isTrue);

        final published = sync.published.length;
        emitNative(target, playing: false, buffering: false);
        expect(sync.published.length, published);
        expect(sync.changes, isEmpty);
        clock.elapse(bridge.settleWindow - const Duration(milliseconds: 1));
        expect(sync.published.length, published);
        clock.elapse(const Duration(milliseconds: 1));
        expect(sync.published.length, published + 1);
        expect(sync.published.last.paused, isTrue);
        expect(sync.changes, [false]);
        expect(target.snapshot.playing, isFalse);

        sync.peer(
          const PeerPlayState(
            position: Duration(seconds: 46),
            paused: false,
            setBy: 'peer',
          ),
        );
        clock.flushMicrotasks();
        expect(target.snapshot.playing, isTrue);
        expect(sync.published.last.paused, isFalse);
      });
    },
  );

  for (final interruption in [
    'native resume',
    'new local intent',
    'new peer intent',
    'new source',
    'dispose',
  ]) {
    test(
      'early native pause reconciliation cancels on $interruption',
      () async {
        await bridge.load(movie);
        await bridge.dispose();
        fakeAsync((clock) {
          bridge = PlaybackSyncBridge(
            target: target,
            sync: sync,
            authorizePlayback: () async => true,
          )..start();
          unawaited(bridge.markSourceOpen(movie.uri.toString()));
          clock.flushMicrotasks();
          sync.peer(remotePlay);
          clock.flushMicrotasks();
          expect(target.snapshot.playing, isTrue);

          emitNative(target, playing: false, buffering: false);
          expect(sync.published.last.paused, isFalse);
          expect(clock.pendingTimers, hasLength(1));

          switch (interruption) {
            case 'native resume':
              emitNative(target, playing: true, buffering: false);
            case 'new local intent':
              unawaited(bridge.pause());
              clock.flushMicrotasks();
            case 'new peer intent':
              sync.peer(
                const PeerPlayState(
                  position: Duration(seconds: 45),
                  paused: true,
                  setBy: 'peer',
                ),
              );
              clock.flushMicrotasks();
            case 'new source':
              bridge.beginSourceLoad();
              unawaited(target.load(second));
              clock.flushMicrotasks();
              unawaited(bridge.markSourceOpen(second.uri.toString()));
              clock.flushMicrotasks();
            case 'dispose':
              unawaited(bridge.dispose());
              clock.flushMicrotasks();
          }
          final published = sync.published.length;
          clock.elapse(bridge.settleWindow);
          expect(sync.published.length, published);
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }

  for (final command in ['play', 'seek']) {
    test(
      '$command during buffering retains intent through READY callback',
      () async {
        await bridge.dispose();
        await target.close();
        final bufferingTarget = BufferingTestTarget();
        target = bufferingTarget;
        bridge = PlaybackSyncBridge(
          target: target,
          sync: sync,
          authorizePlayback: () async => true,
        )..start();
        await bridge.load(movie);
        await bridge.play();
        emitNative(target, playing: false, buffering: true);
        bufferingTarget.bufferCommands = true;
        if (command == 'play') {
          expect(await bridge.play(), isTrue);
        } else {
          await bridge.seek(const Duration(seconds: 20));
        }
        expect(target.snapshot.buffering, isTrue);
        expect(target.snapshot.playing, isFalse);
        expect(sync.published.last.paused, isFalse);
        emitNative(target, playing: false, buffering: false);
        expect(sync.published.last.paused, isFalse);
        emitNative(target, playing: true, buffering: false);
        expect(sync.published.last.paused, isFalse);
      },
    );
  }

  test('late native play echo cannot undo an expected peer pause', () async {
    await bridge.load(movie);
    var checks = 0;
    authorize = () async {
      checks++;
      return true;
    };
    sync.peer(
      const PeerPlayState(
        position: Duration(seconds: 12),
        paused: true,
        setBy: 'peer',
      ),
    );
    await until(() => target.snapshot.position.inSeconds == 12);
    emitNative(target, playing: true, buffering: false);
    await Future<void>.delayed(Duration.zero);
    expect(checks, 0);
    expect(target.commands, isNot(contains('play')));
    expect(sync.published.last.paused, isTrue);
  });

  test(
    'native play echo after expired settle window cannot undo peer pause',
    () async {
      await bridge.load(movie);
      await bridge.dispose();
      fakeAsync((clock) {
        var checks = 0;
        bridge = PlaybackSyncBridge(
          target: target,
          sync: sync,
          authorizePlayback: () async {
            checks++;
            return true;
          },
          settleWindow: Duration.zero,
        )..start();
        unawaited(bridge.markSourceOpen(movie.uri.toString()));
        clock.flushMicrotasks();

        sync.peer(
          const PeerPlayState(
            position: Duration(seconds: 12),
            paused: true,
            setBy: 'peer',
          ),
        );
        clock.flushMicrotasks();
        expect(target.snapshot.position, const Duration(seconds: 12));
        expect(sync.published.last.paused, isTrue);
        final playsBeforeEcho = target.commands
            .where((command) => command == 'play')
            .length;
        final pausesBeforeEcho = target.commands
            .where((command) => command == 'pause')
            .length;

        emitNative(target, playing: true, buffering: false);
        emitNative(target, playing: true, buffering: false);
        emitNative(target, playing: true, buffering: false);
        clock.flushMicrotasks();

        expect(checks, 0);
        expect(
          target.commands.where((command) => command == 'play').length,
          playsBeforeEcho,
        );
        expect(
          target.commands.where((command) => command == 'pause').length,
          pausesBeforeEcho + 1,
        );
        expect(target.snapshot.playing, isFalse);
        expect(sync.published.last.paused, isTrue);

        bool? played;
        unawaited(bridge.play().then((value) => played = value));
        clock.flushMicrotasks();
        expect(played, isTrue);
        expect(checks, 1);
        expect(target.snapshot.playing, isTrue);
      });
    },
  );

  test('stale pause correction cannot affect a replacement source', () async {
    await bridge.dispose();
    await target.close();
    final gatedTarget = PauseCompletionGatedTarget();
    target = gatedTarget;
    bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () async => true,
      onError: errors.add,
      settleWindow: Duration.zero,
    )..start();
    await bridge.load(movie);
    final pauseCompletion = Completer<void>();
    gatedTarget.pauseCompletionGate = pauseCompletion;

    emitNative(target, playing: true, buffering: false);
    await until(() => target.commands.contains('pause'));
    bridge.beginSourceLoad();
    await target.load(second);
    await target.play();
    final publicationsBeforeCompletion = sync.published.length;

    pauseCompletion.complete();
    await Future<void>.delayed(Duration.zero);

    expect(target.snapshot.media, second);
    expect(target.snapshot.playing, isTrue);
    expect(sync.published.length, publicationsBeforeCompletion);
  });

  test('late external play authorization cannot undo a user pause', () async {
    await bridge.dispose();
    await target.close();
    target = ExternalPlaybackTestTarget();
    bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      authorizePlayback: () => authorize(),
      onError: errors.add,
    )..start();
    await bridge.load(movie);
    final gate = Completer<bool>();
    authorize = () => gate.future;
    emitNative(target, playing: true, buffering: false);
    await until(() => target.commands.contains('pause'));
    expect(sync.published.last.paused, isTrue);
    await bridge.pause();
    gate.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(target.commands, isNot(contains('play')));
    expect(sync.published.every((state) => state.paused), isTrue);
  });

  for (final allowed in [true, false]) {
    test(
      'external-capable play after peer pause is quota ${allowed ? 'authorized' : 'blocked'}',
      () async {
        await bridge.dispose();
        await target.close();
        target = ExternalPlaybackTestTarget();
        var checks = 0;
        bridge = PlaybackSyncBridge(
          target: target,
          sync: sync,
          authorizePlayback: () async {
            checks++;
            return allowed;
          },
          onError: errors.add,
          settleWindow: Duration.zero,
        )..start();
        await bridge.load(movie);
        sync.peer(
          const PeerPlayState(
            position: Duration(seconds: 12),
            paused: true,
            setBy: 'peer',
          ),
        );
        await until(() => target.snapshot.position.inSeconds == 12);
        target.commands.clear();

        emitNative(target, playing: true, buffering: false);
        await until(() => checks == 1);
        await Future<void>.delayed(Duration.zero);

        expect(checks, 1);
        expect(
          target.commands.where((command) => command == 'play').length,
          allowed ? 1 : 0,
        );
        expect(target.snapshot.playing, allowed);
        expect(sync.published.last.paused, !allowed);
      },
    );
  }

  test(
    'buffering native events cannot pause a real second Syncplay client',
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
      await firstBridge.play();
      await until(() => secondTarget.snapshot.playing);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final beforeBuffer = server.acceptedChanges.length;

      // ExoPlayer sends STATE_BUFFERING and then onIsPlayingChanged(false)
      // while playWhenReady remains true. Flutter exposes separate snapshots.
      emitNative(firstTarget, playing: true, buffering: true);
      emitNative(firstTarget, playing: false, buffering: true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.roomPaused, isFalse);
      expect(secondTarget.snapshot.playing, isTrue);
      expect(server.acceptedChanges.length, beforeBuffer);

      // READY arrives before the matching isPlaying=true callback as well.
      emitNative(firstTarget, playing: false, buffering: false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.roomPaused, isFalse);
      emitNative(firstTarget, playing: true, buffering: false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.acceptedChanges.length, beforeBuffer);

      emitNative(firstTarget, playing: false, buffering: true);
      await firstBridge.pause();
      await until(() => server.roomPaused && !secondTarget.snapshot.playing);
      expect(server.roomSetBy, 'alice');
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

  group('native rate correction', () {
    late RateTestTarget rateTarget;

    Future<void> useRateTarget({
      Duration commandTimeout = const Duration(seconds: 5),
      Duration rateCorrectionWindow = const Duration(seconds: 25),
    }) async {
      await bridge.dispose();
      await target.close();
      rateTarget = RateTestTarget();
      target = rateTarget;
      bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
        onError: errors.add,
        commandTimeout: commandTimeout,
        rateCorrectionWindow: rateCorrectionWindow,
      )..start();
      await bridge.load(movie);
      sync.connection(SyncConnectionStatus.connected);
      await bridge.play();
      target.commands.clear();
      sync.changes.clear();
    }

    void heartbeat(
      Duration position, {
      bool paused = false,
      bool seek = false,
    }) {
      sync.lastAdvancingRoomState = PeerPlayState(
        position: position,
        paused: paused,
        doSeek: seek,
        setBy: 'peer',
      );
    }

    test(
      'ahead playback slows then converges without seek or room echo',
      () async {
        await useRateTarget();
        heartbeat(const Duration(seconds: 8));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.contains(0.90));
        heartbeat(const Duration(milliseconds: 9600));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.last == 1);
        expect(target.commands, isEmpty);
        expect(sync.changes, isEmpty);
      },
    );

    test(
      'strong correction reaches subsecond sync through moderate drift',
      () async {
        await useRateTarget();
        var roomMs = 30000;
        var nativeMs = 31600;
        // Model two advancing decoders after the slower player becomes the
        // room anchor. Feed the rate actually requested by the bridge back
        // into the leading decoder; no peer seek or user command occurs.
        for (var tick = 0; tick < 14; tick++) {
          heartbeat(Duration(milliseconds: roomMs));
          emitNativePosition(
            target,
            Duration(milliseconds: nativeMs),
            playing: true,
          );
          // Drain the serialized native command, without waiting for a real
          // seven-second movie. Each pair above is a fresh room observation.
          await Future<void>.delayed(Duration.zero);
          final rate = rateTarget.rates.isEmpty ? 1.0 : rateTarget.rates.last;
          roomMs += 500;
          nativeMs += (500 * rate).round();
        }
        expect(nativeMs - roomMs, lessThan(1000));
        expect(target.commands, isEmpty);
        expect(sync.changes, isEmpty);

        // Once close, keep the gentler finish and then restore normal speed.
        heartbeat(Duration(milliseconds: nativeMs - 700));
        emitNativePosition(
          target,
          Duration(milliseconds: nativeMs),
          playing: true,
        );
        await until(() => rateTarget.rates.last == 0.95);
        heartbeat(Duration(milliseconds: nativeMs - 400));
        emitNativePosition(
          target,
          Duration(milliseconds: nativeMs),
          playing: true,
        );
        await until(() => rateTarget.rates.last == 1);
      },
    );

    test(
      'buffer chatter restores 1x and waits for stable ready playback',
      () async {
        await useRateTarget();
        heartbeat(const Duration(seconds: 8));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.contains(0.90));

        for (var i = 0; i < 3; i++) {
          emitNative(target, playing: false, buffering: true);
          await until(() => rateTarget.rates.last == 1);
          heartbeat(const Duration(seconds: 8));
          emitNative(target, playing: true, buffering: false);
          await Future<void>.delayed(const Duration(milliseconds: 120));
          heartbeat(const Duration(seconds: 8));
          emitNativePosition(
            target,
            const Duration(seconds: 10),
            playing: true,
          );
          expect(rateTarget.rates, [0.90, 1]);
        }

        await Future<void>.delayed(const Duration(milliseconds: 950));
        heartbeat(const Duration(milliseconds: 8900));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.last == 0.90);
        expect(rateTarget.rates, [0.90, 1, 0.90]);
        expect(target.commands, isEmpty);
        expect(sync.changes, isEmpty);
      },
    );

    test(
      'buffer recovery below 900 ms leaves the strong correction band',
      () async {
        await useRateTarget();
        heartbeat(const Duration(seconds: 8));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.contains(0.90));
        emitNative(target, playing: false, buffering: true);
        await until(() => rateTarget.rates.last == 1);
        emitNative(target, playing: true, buffering: false);
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        heartbeat(const Duration(milliseconds: 9200));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await Future<void>.delayed(Duration.zero);
        expect(rateTarget.rates, [0.90, 1]);
        heartbeat(const Duration(milliseconds: 10400));
        emitNativePosition(
          target,
          const Duration(milliseconds: 11500),
          playing: true,
        );
        await until(() => rateTarget.rates.last == 0.95);
        expect(target.commands, isEmpty);
        expect(sync.changes, isEmpty);
      },
    );

    test('buffer recovery keeps the original correction window', () async {
      await useRateTarget(
        rateCorrectionWindow: const Duration(milliseconds: 100),
      );
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      emitNative(target, playing: false, buffering: true);
      await until(() => rateTarget.rates.last == 1);
      emitNative(target, playing: true, buffering: false);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      expect(rateTarget.rates, [0.90, 1]);
    });

    test('buffer recovery requires a heartbeat after ready playback', () async {
      await useRateTarget();
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      emitNative(target, playing: false, buffering: true);
      await until(() => rateTarget.rates.last == 1);
      heartbeat(const Duration(seconds: 8));
      emitNative(target, playing: true, buffering: false);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      expect(rateTarget.rates, [0.90, 1]);
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.last == 0.90);
    });

    test(
      'stale, paused, seek and absent heartbeat cannot start slowdown',
      () async {
        await useRateTarget();
        for (final state in [
          const PeerPlayState(
            position: Duration(seconds: 8),
            paused: true,
            setBy: 'peer',
          ),
          const PeerPlayState(
            position: Duration(seconds: 8),
            paused: false,
            doSeek: true,
            setBy: 'peer',
          ),
        ]) {
          sync.lastAdvancingRoomState = state;
          emitNativePosition(
            target,
            const Duration(seconds: 10),
            playing: true,
          );
        }
        sync.lastAdvancingRoomState = null;
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        heartbeat(const Duration(seconds: 8));
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        expect(rateTarget.rates, isEmpty);
      },
    );

    test('new intent and source restore 1x after in-flight slowdown', () async {
      await useRateTarget();
      final gate = Completer<void>();
      rateTarget.rateGate = gate;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      final paused = bridge.pause();
      gate.complete();
      await paused;
      await until(() => rateTarget.rates.last == 1);
      expect(target.snapshot.playing, isFalse);
      bridge.beginSourceLoad();
      await target.load(second);
      expect(rateTarget.rates.last, 1);
      expect(sync.changes, [false]);
    });

    test('disposal restores rate when the reset is already queued', () async {
      await useRateTarget();
      final gate = Completer<void>();
      rateTarget.rateGate = gate;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      final paused = bridge.pause();
      await bridge.dispose();
      expect(rateTarget.rates.last, 1);
      gate.complete();
      await paused;
      expect(rateTarget.rates.last, 1);
    });

    test('disposed bridge cannot reset a replacement bridge rate', () async {
      await useRateTarget();
      final oldBridge = bridge;
      final gate = Completer<void>();
      rateTarget.rateGate = gate;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      oldBridge.beginSourceLoad(); // Queues 1x behind the in-flight slowdown.
      await oldBridge.dispose(); // Direct final 1x restore.
      expect(rateTarget.rates, [0.90, 1]);

      bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
        onError: errors.add,
      )..start();
      await bridge.markSourceOpen(movie.uri.toString());
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.last == 0.90);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(rateTarget.rates.last, 0.90);
      expect(rateTarget.rates, [0.90, 1, 0.90]);
    });

    test('source replacement and disposal restore rate', () async {
      await useRateTarget();
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      bridge.beginSourceLoad();
      await until(() => rateTarget.rates.last == 1);
      await target.load(second);
      expect(rateTarget.rates.last, 1);

      await bridge.markSourceOpen(second.uri.toString());
      await bridge.play();
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.last == 0.90);
      await bridge.dispose();
      expect(rateTarget.rates.last, 1);
    });

    test('in-flight slowdown cannot survive source replacement', () async {
      await useRateTarget();
      final gate = Completer<void>();
      rateTarget.rateGate = gate;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      bridge.beginSourceLoad();
      await target.load(second);
      gate.complete();
      await until(() => rateTarget.rates.last == 1);
      await bridge.markSourceOpen(second.uri.toString());
      expect(rateTarget.rates, [0.90, 1]);
    });

    test('failed 1x restore retries once before allowing slowdown', () async {
      await useRateTarget();
      rateTarget.resetFailures = 1;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      heartbeat(const Duration(milliseconds: 9600));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => errors.isNotEmpty);
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      expect(rateTarget.rates.where((rate) => rate < 1), [0.90]);
      await until(
        () => rateTarget.rates.where((rate) => rate == 1).length == 2,
      );
      expect(rateTarget.rates, [0.90, 1, 1]);
    });

    test(
      'timed-out 1x restore retries and late completion is harmless',
      () async {
        await useRateTarget(commandTimeout: const Duration(milliseconds: 30));
        final gate = Completer<void>();
        rateTarget.resetGate = gate;
        heartbeat(const Duration(seconds: 8));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => rateTarget.rates.contains(0.90));
        heartbeat(const Duration(milliseconds: 9600));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        await until(() => errors.whereType<TimeoutException>().isNotEmpty);
        await until(
          () => rateTarget.rates.where((rate) => rate == 1).length == 2,
        );
        gate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(rateTarget.rates, [0.90, 1, 1]);
      },
    );

    test('persistent 1x failures stop after three attempts', () async {
      await useRateTarget();
      rateTarget.resetFailures = 99;
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(() => rateTarget.rates.contains(0.90));
      heartbeat(const Duration(milliseconds: 9600));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await until(
        () => rateTarget.rates.where((rate) => rate == 1).length == 3,
      );
      heartbeat(const Duration(seconds: 8));
      emitNativePosition(target, const Duration(seconds: 10), playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(rateTarget.rates, [0.90, 1, 1, 1]);
      expect(errors.length, 3);
    });

    test(
      'unsupported target keeps ordinary playback with no corrective command',
      () async {
        await bridge.load(movie);
        sync.connection(SyncConnectionStatus.connected);
        await bridge.play();
        target.commands.clear();
        sync.changes.clear();
        heartbeat(const Duration(seconds: 8));
        emitNativePosition(target, const Duration(seconds: 10), playing: true);
        expect(target.commands, isEmpty);
        expect(sync.changes, isEmpty);
      },
    );
  });
}

void emitNative(
  SyncTestTarget target, {
  required bool playing,
  required bool buffering,
}) {
  final state = target.snapshot;
  target.emit(
    PlaybackSnapshot(
      media: state.media,
      position: state.position,
      duration: state.duration,
      playing: playing,
      buffering: buffering,
      connection: state.connection,
    ),
  );
}

void emitNativePosition(
  SyncTestTarget target,
  Duration position, {
  required bool playing,
}) {
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

class DelayedPlayTarget extends SyncTestTarget {
  @override
  Future<void> play() async {
    // The platform play request completes before the decoder advances.
    commands.add('play');
  }
}

class HandoffDelayedTarget extends SyncTestTarget {
  bool firstPlay = true;

  @override
  Future<void> play() async {
    if (firstPlay) {
      firstPlay = false;
      await super.play();
    } else {
      commands.add('play');
    }
  }
}

class BufferingTestTarget extends SyncTestTarget {
  bool bufferCommands = false;

  @override
  Future<void> play() async {
    await super.play();
    if (bufferCommands) emitNative(this, playing: false, buffering: true);
  }

  @override
  Future<void> seek(Duration position) async {
    await super.seek(position);
    if (bufferCommands) emitNative(this, playing: false, buffering: true);
  }
}

class ExternalPlaybackTestTarget extends SyncTestTarget {
  @override
  bool get acceptsExternalPlaybackChanges => true;
}

class PauseCompletionGatedTarget extends SyncTestTarget {
  Completer<void>? pauseCompletionGate;

  @override
  Future<void> pause() async {
    await super.pause();
    final gate = pauseCompletionGate;
    pauseCompletionGate = null;
    await gate?.future;
  }
}

class RateTestTarget extends SyncTestTarget implements PlaybackRateTarget {
  final rates = <double>[];
  Completer<void>? rateGate;
  Completer<void>? resetGate;
  int resetFailures = 0;

  @override
  Future<void> setPlaybackRate(double rate) async {
    rates.add(rate);
    if (rate == 1 && resetFailures > 0) {
      resetFailures--;
      throw StateError('native rate reset failed');
    }
    final pendingReset = rate == 1 ? resetGate : null;
    if (rate == 1) resetGate = null;
    final gate = rateGate;
    rateGate = null;
    await gate?.future;
    await pendingReset?.future;
  }
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
