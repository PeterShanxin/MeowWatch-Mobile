import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';

import '../support/sync_playback_fakes.dart';

class ControlledRepository extends AppRepository {
  ControlledRepository() : super(File('unused-controller-test-history.json'));
  bool failWrite = false;
  @override
  Future<void> save() async {
    if (failWrite) throw const FileSystemException('disk full');
  }
}

class ControlledQuota implements HostingAccessPolicy {
  Completer<bool>? gate;
  Completer<SessionStartResult>? startGate;
  int checks = 0;
  int starts = 0;
  @override
  Future<bool> canHostNow({String? sessionId}) async {
    checks++;
    return gate == null ? true : gate!.future;
  }

  @override
  Future<int> remainingFreeHostsToday() async => 1;
  @override
  Future<SessionStartResult> recordSessionStarted({
    required String sessionId,
    required bool isCreator,
    required int peerCount,
    required bool synchronizedPlaybackActive,
    bool explicitStart = false,
  }) async {
    starts++;
    return startGate == null
        ? SessionStartResult.freeStarted
        : startGate!.future;
  }
}

class ControlledClient extends SyncplayClient {
  Completer<void>? joinGate;
  VoidCallback? joined;
  bool closed = false;
  bool dialed = false;
  int changes = 0;
  String? receivedPassword;
  String? receivedServer;
  int? receivedPort;
  String? joinError;

  void peer(PeerPlayState state) {
    lastObservedRoomState = state;
    emitPeerState(state);
  }

  @override
  Future<String?> connectUntilJoin({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
    Future<void> Function()? onHandoff,
  }) async {
    dialed = true;
    receivedPassword = password;
    receivedServer = server;
    receivedPort = port;
    if (joinError != null) return joinError;
    if (joinGate != null) await joinGate!.future;
    joined?.call();
    emitConnectionState(
      SyncConnectionState(
        status: SyncConnectionStatus.connected,
        username: username,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return null;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {
    changes++;
  }

  @override
  void updateLocalState({required Duration position, required bool paused}) {}
  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}
  @override
  Future<void> disposeBackend() async {
    closed = true;
  }
}

typedef VoidCallback = void Function();

final media = MediaItem(
  uri: Uri.parse('https://example.com/movie.mp4'),
  title: 'Movie',
);

class DeferredResumeTarget extends SyncTestTarget {
  Completer<void>? beforeLoad;
  bool waitingBeforeLoad = false;

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final gate = beforeLoad;
    beforeLoad = null;
    if (gate != null) {
      waitingBeforeLoad = true;
      await gate.future;
      waitingBeforeLoad = false;
    }
    await super.load(media, position: position);
  }
}

const ticket = RoomTicket(
  id: 'persistent-host',
  isHost: true,
  config: RoomConfig(
    server: 'syncplay.pl',
    port: 8995,
    room: 'room',
    username: 'Host',
    password: 'server-password',
  ),
);

void main() {
  late AppController app;
  late ControlledRepository repository;
  late ControlledQuota quota;
  late DeferredResumeTarget target;
  late ControlledClient client;
  ControlledClient Function()? clientFactory;
  var clientsCreated = 0;
  setUp(() {
    repository = ControlledRepository();
    quota = ControlledQuota();
    target = DeferredResumeTarget();
    client = ControlledClient();
    clientFactory = null;
    clientsCreated = 0;
    app = AppController(
      repository: repository,
      billing: RevenueCatBillingService(apiKey: ''),
      hosting: quota,
      phone: target,
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () {
        clientsCreated++;
        return clientFactory?.call() ?? client;
      },
    );
  });
  tearDown(() async {
    repository.failWrite = false;
    try {
      await app.close();
    } on FileSystemException {
      // A close already observed by the test preserves its original error.
    }
  });

  WatchHistoryEntry pastNight() => WatchHistoryEntry(
    media: media,
    position: const Duration(seconds: 24),
    duration: const Duration(minutes: 10),
    updatedAt: DateTime(2026, 9, 15),
    room: ticket,
  );

  test('pause tap during room buffering uses accepted play intent', () async {
    await app.load(media);
    expect(await app.connect(ticket), isTrue);
    await app.togglePlay();
    target.emit(
      PlaybackSnapshot(
        media: media,
        duration: const Duration(minutes: 5),
        playing: false,
        buffering: true,
        connection: PlaybackConnection.ready,
      ),
    );
    expect(target.snapshot.playing, isFalse);
    expect(app.playRequested, isTrue);
    final before = target.commands.length;
    await app.togglePlay();
    expect(target.commands.skip(before), ['pause']);
    expect(app.playRequested, isFalse);
  });

  test(
    'background phone ignores remote play until visible Play action',
    () async {
      await app.load(media);
      expect(await app.connect(ticket), isTrue);
      await app.togglePlay();
      await app.background();
      final starts = quota.starts;
      target.commands.clear();
      const peerPlay = PeerPlayState(
        position: Duration(seconds: 12),
        paused: false,
        setBy: 'Peer',
      );
      client.peer(peerPlay);
      await until(() => target.commands.isNotEmpty);
      expect(target.commands, isNot(contains('play')));
      expect(target.snapshot.playing, isFalse);
      expect(quota.starts, starts);
      await app.togglePlay();
      expect(target.snapshot.playing, isFalse);
      app.foreground();
      target.commands.clear();
      client.peer(peerPlay);
      await until(() => target.commands.isNotEmpty);
      expect(target.commands, isNot(contains('play')));
      expect(quota.starts, starts);
      await app.togglePlay();
      expect(target.snapshot.playing, isTrue);
      expect(app.isConnected, isTrue);
    },
  );

  test('background cancels peer play waiting on a native seek', () async {
    await app.load(media);
    expect(await app.connect(ticket), isTrue);
    final gate = target.seekGate = Completer<void>();
    target.commands.clear();
    client.peer(
      const PeerPlayState(
        position: Duration(seconds: 18),
        paused: false,
        setBy: 'Peer',
      ),
    );
    await until(() => target.commands.contains('seek:18000'));
    final backgrounding = app.background();
    gate.complete();
    await backgrounding;
    expect(target.commands, isNot(contains('play')));
    expect(target.snapshot.playing, isFalse);
  });

  test('late quota authorization cannot restart a background phone', () async {
    await app.load(media);
    expect(await app.connect(ticket), isTrue);
    quota.startGate = Completer<SessionStartResult>();
    target.commands.clear();
    client.peer(
      const PeerPlayState(
        position: Duration(seconds: 18),
        paused: false,
        setBy: 'Peer',
      ),
    );
    await until(() => quota.starts == 1);
    await app.background();
    app.foreground();
    quota.startGate!.complete(SessionStartResult.freeStarted);
    await Future<void>.delayed(Duration.zero);
    expect(target.commands, isNot(contains('play')));
    expect(target.snapshot.playing, isFalse);
    expect(app.isConnected, isTrue);
  });

  test(
    'resumed load completing after HOME stays paused after foreground',
    () async {
      client.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 40),
        paused: false,
        setBy: 'Peer',
      );
      final gate = target.loadGate = Completer<void>();
      final resuming = app.resume(pastNight());
      await until(
        () => target.snapshot.media != null && !target.snapshot.ready,
      );
      await app.background();
      app.foreground();
      gate.complete();
      await resuming;
      expect(target.snapshot.ready, isTrue);
      expect(target.commands, isNot(contains('play')));
      expect(target.snapshot.playing, isFalse);
      expect(quota.starts, 0);
      await app.togglePlay();
      expect(target.snapshot.playing, isTrue);
    },
  );

  test(
    'same-source history restore blocks old controls until load completes',
    () async {
      await app.load(media);
      final gate = target.beforeLoad = Completer<void>();
      final restoreStates = <bool>[];
      app.addListener(() => restoreStates.add(app.isRestoringHistory));
      target.commands.clear();

      final restoring = app.resume(pastNight());
      await until(() => target.waitingBeforeLoad);
      expect(app.isRestoringHistory, isTrue);
      expect(app.busy, isFalse);
      expect(target.snapshot.ready, isTrue);
      expect(target.snapshot.media?.uri, media.uri);
      await app.togglePlay();
      await app.seek(const Duration(seconds: 45));
      expect(target.commands, isNot(contains('play')));
      expect(target.commands, isNot(contains('seek:45000')));

      gate.complete();
      await restoring;
      expect(app.isRestoringHistory, isFalse);
      expect(restoreStates, containsAllInOrder([true, false]));
      expect(target.snapshot.ready, isTrue);
      await app.togglePlay();
      expect(
        target.commands.where((command) => command == 'play'),
        hasLength(1),
      );
      expect(target.snapshot.playing, isTrue);
    },
  );

  test('failed history restore clears its visible loading state', () async {
    repository.failWrite = true;
    final restoreStates = <bool>[];
    app.addListener(() => restoreStates.add(app.isRestoringHistory));
    await app.resume(pastNight());
    expect(app.isRestoringHistory, isFalse);
    expect(restoreStates, containsAllInOrder([true, false]));
    expect(target.commands, isNot(contains('play')));
  });

  test(
    'history pins room A after a later new room falls back to server B',
    () async {
      final attempts = <ControlledClient>[];
      clientFactory = () {
        final next = ControlledClient();
        if (attempts.length == 1) next.joinError = 'Endpoint unavailable';
        attempts.add(next);
        return next;
      };
      expect(await app.createRoom(), isTrue);
      await app.load(media);
      final first = repository.history.first;
      expect(first.room!.config.port, 8995);
      expect(first.room!.config.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(await app.createRoom(), isTrue);
      expect(app.room!.config.port, 8996);
      expect(app.room!.id, isNot(first.room!.id));
      await app.resume(first);
      expect(attempts.map((attempt) => attempt.receivedPort), [
        8995,
        8995,
        8996,
        8995,
      ]);
      expect(attempts.last.receivedServer, first.room!.config.server);
      expect(app.room!.id, first.room!.id);
      expect(app.room!.config.port, first.room!.config.port);
      expect(target.snapshot.media!.uri, media.uri);
    },
  );

  test('watch again creates a fresh host room with the saved video', () async {
    expect(await app.watchAgain(pastNight()), isTrue);
    expect(app.isRestoringHistory, isFalse);
    expect(app.room!.isHost, isTrue);
    expect(app.room!.id, isNot(ticket.id));
    expect(app.room!.config.room, isNot(ticket.config.room));
    expect(target.snapshot.media!.uri, media.uri);
    expect(target.snapshot.position, const Duration(seconds: 24));
    expect(target.snapshot.playing, isFalse);
    expect(quota.checks, 1);
    expect(quota.starts, 0);
    expect(repository.history.first.room!.id, app.room!.id);
  });

  test(
    'watch again still checks quota and preserves local video if denied',
    () async {
      await app.useLocalMode();
      final previous = MediaItem.fromUrl('https://example.com/current.mp4');
      await app.load(previous);
      quota.gate = Completer<bool>()..complete(false);
      expect(await app.watchAgain(pastNight()), isFalse);
      expect(app.needsPlus, isTrue);
      expect(app.room, isNull);
      expect(target.snapshot.media!.uri, previous.uri);
      expect(clientsCreated, 0);
      expect(quota.starts, 0);
    },
  );

  test('cancelled repeat connection never loads the saved video', () async {
    quota.gate = Completer<bool>();
    final restoreStates = <bool>[];
    app.addListener(() => restoreStates.add(app.isRestoringHistory));
    final pending = app.watchAgain(pastNight());
    expect(app.isRestoringHistory, isTrue);
    expect(await app.watchAgain(pastNight()), isFalse);
    await app.leavePlayer();
    quota.gate!.complete(true);
    expect(await pending, isFalse);
    expect(app.isRestoringHistory, isFalse);
    expect(restoreStates, containsAllInOrder([true, false]));
    expect(target.snapshot.media, isNull);
    expect(app.room, isNull);
    expect(clientsCreated, 0);
  });

  test(
    'shutdown releases network and player when history cannot save',
    () async {
      await app.load(media);
      expect(await app.connect(ticket), isTrue);
      final playerClosed = Completer<void>();
      target.states.listen((_) {}, onDone: playerClosed.complete);
      repository.failWrite = true;
      final closing = app.close();
      expect(identical(closing, app.close()), isTrue);
      await expectLater(closing, throwsA(isA<FileSystemException>()));
      await playerClosed.future.timeout(const Duration(seconds: 1));
      expect(client.closed, isTrue);
    },
  );

  test('double start is serialized before asynchronous quota access', () async {
    quota.gate = Completer<bool>();
    final first = app.connect(ticket);
    expect(app.busy, isTrue);
    expect(await app.connect(ticket), isFalse);
    quota.gate!.complete(true);
    expect(await first, isTrue);
    expect(quota.checks, 1);
    expect(clientsCreated, 1);
    expect(client.receivedPassword, 'server-password');
  });

  test(
    'late hosting denial cannot open a paywall in a new local session',
    () async {
      await app.load(media);
      expect(await app.connect(ticket), isTrue);
      quota.startGate = Completer<SessionStartResult>();
      final playing = app.togglePlay();
      await until(() => quota.starts == 1);
      await app.useLocalMode();
      quota.startGate!.complete(SessionStartResult.quotaExceeded);
      await playing;
      expect(app.needsPlus, isFalse);
      expect(app.isLocal, isTrue);
      expect(target.snapshot.playing, isFalse);
    },
  );

  test('leaving during dial cannot resurrect room or player', () async {
    client.joinGate = Completer<void>();
    final connecting = app.connect(ticket);
    await until(() => client.dialed);
    await app.leavePlayer();
    client.joinGate!.complete();
    expect(await connecting, isFalse);
    expect(app.room, isNull);
    expect(app.inPlayer, isFalse);
    expect(app.isConnected, isFalse);
    expect(client.closed, isTrue);
  });

  test('cancelling during quota lookup never starts a socket', () async {
    quota.gate = Completer<bool>();
    final connecting = app.connect(ticket);
    await app.useLocalMode();
    quota.gate!.complete(true);
    expect(await connecting, isFalse);
    expect(clientsCreated, 0);
    expect(app.isLocal, isTrue);
  });

  test('disk failure after Hello leaves no half-connected session', () async {
    client.joined = () {
      repository.failWrite = true;
    };
    expect(await app.connect(ticket), isFalse);
    expect(app.room, isNull);
    expect(app.isConnected, isFalse);
    expect(client.closed, isTrue);
    expect(app.message, contains('storage'));
  });

  test(
    'local load finishing after room connection confirms current source',
    () async {
      final gate = Completer<void>();
      target.loadGate = gate;
      final loading = app.load(media);
      await until(
        () => target.snapshot.media?.uri == media.uri && !target.snapshot.ready,
      );
      expect(await app.connect(ticket), isTrue);
      gate.complete();
      await loading;
      await app.togglePlay();
      expect(target.snapshot.playing, isTrue);
      expect(client.changes, greaterThan(0));
    },
  );

  test('resume does not adopt or start the previously loaded movie', () async {
    await app.load(media);
    target.commands.clear();
    client.lastObservedRoomState = const PeerPlayState(
      position: Duration(seconds: 20),
      paused: false,
      setBy: 'Peer',
    );
    final gate = Completer<void>();
    target.loadGate = gate;
    final nextMedia = MediaItem(
      uri: Uri.parse('https://example.com/next.mp4'),
      title: 'Next',
    );
    final resuming = app.resume(
      WatchHistoryEntry(
        media: nextMedia,
        position: const Duration(seconds: 7),
        duration: const Duration(minutes: 5),
        updatedAt: DateTime(2026, 9, 16),
        room: ticket,
      ),
    );
    await until(
      () =>
          target.snapshot.media?.uri == nextMedia.uri && !target.snapshot.ready,
    );
    expect(target.commands, isNot(contains('play')));
    expect(quota.starts, 0);
    gate.complete();
    await resuming;
    expect(target.snapshot.media?.uri, nextMedia.uri);
  });
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
