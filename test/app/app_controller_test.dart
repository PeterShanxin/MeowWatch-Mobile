import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
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
  late SyncTestTarget target;
  late ControlledClient client;
  var clientsCreated = 0;
  setUp(() {
    repository = ControlledRepository();
    quota = ControlledQuota();
    target = SyncTestTarget();
    client = ControlledClient();
    clientsCreated = 0;
    app = AppController(
      repository: repository,
      billing: RevenueCatBillingService(apiKey: ''),
      hosting: quota,
      phone: target,
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () {
        clientsCreated++;
        return client;
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
