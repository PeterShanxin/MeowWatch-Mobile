import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/cast/cast_playback_target.dart';
import 'package:meowwatch_mobile/core/cast/cast_transport.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../support/sync_playback_fakes.dart';
import '../support/syncplay_room_server.dart';
import 'app_controller_test.dart' as support;

final movie = MediaItem.fromUrl('https://media.example.com/movie.mp4');

class _Repository extends support.ControlledRepository {
  Completer<void>? gate;
  @override
  Future<void> save() async {
    await gate?.future;
    await super.save();
  }
}

class _Store implements HostingQuotaStore {
  String? data;
  int writes = 0;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async {
    data = value;
    writes++;
  }
}

// A receiver API double, not native Cast/hardware evidence. The production
// CastPlaybackTarget still validates status, tokens and command completions.
class _Receiver implements CastTransport {
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final calls = <String>[];
  int revision = 0;
  String? token;
  String? owner;
  String session = 'connected';
  String player = 'paused';
  int position = 0;
  String? fail;
  Completer<void>? connectGate;
  void Function()? beforePlay;
  Map<Object?, Object?> state() => {
    'generation': 1,
    'owner': owner,
    'revision': ++revision,
    'session': session,
    'player': player,
    'receiverName': 'Test TV',
    'mediaToken': token,
    'positionMs': position,
    'durationMs': 300000,
  };
  void emit() => eventsController.add(state());
  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;
  @override
  Future<Map<Object?, Object?>> invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add(method);
    if (method == 'connect') {
      owner = arguments['owner'] as String;
      await connectGate?.future;
    }
    if (method == fail) throw PlatformException(code: 'cast_command_failed');
    switch (method) {
      case 'load':
        token = arguments['mediaToken'] as String;
        position = arguments['positionMs'] as int;
        player = 'paused';
      case 'play':
        beforePlay?.call();
        player = 'playing';
      case 'pause':
        player = 'paused';
      case 'seek':
        position = arguments['positionMs'] as int;
      case 'disconnect':
        session = 'disconnected';
    }
    return state();
  }
}

class _RoomClient extends SyncplayClient {
  _RoomClient(this.server);
  final SyncplayRoomServer server;
  int joins = 0;
  @override
  Future<String?> connectUntilJoin({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
    Future<void> Function()? onHandoff,
  }) async {
    joins++;
    await this.server.dial(this, name: username);
    emitConnectionState(
      SyncConnectionState(
        status: SyncConnectionStatus.connected,
        username: username,
      ),
    );
    // The second watcher has actually dialed the loopback server before this
    // call; its state-only fixture does not implement the List command.
    emitInitialRoster(['guest']);
    await Future<void>.delayed(Duration.zero);
    return null;
  }
}

void main() {
  late AppController app;
  late SyncTestTarget phone;
  late _Repository repository;
  late _Receiver receiver;
  late CastPlaybackTarget cast;
  late _Store store;
  late LocalHostingAccessPolicy quota;
  late SyncplayRoomServer server;
  late _RoomClient client;
  late SyncplayClient guest;
  int clientsCreated = 0;
  setUp(() async {
    phone = SyncTestTarget();
    receiver = _Receiver();
    cast = CastPlaybackTarget(transport: receiver);
    repository = _Repository();
    store = _Store();
    quota = LocalHostingAccessPolicy(store: store, isPlus: () => false);
    server = await SyncplayRoomServer.start();
    client = _RoomClient(server);
    guest = SyncplayClient();
    await server.dial(guest, name: 'guest');
    clientsCreated = 0;
    app = AppController(
      repository: repository,
      billing: RevenueCatBillingService(apiKey: ''),
      hosting: quota,
      phone: phone,
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () {
        clientsCreated++;
        return client;
      },
    );
  });
  tearDown(() async {
    repository.failWrite = false;
    await app.close();
    await cast.close();
    await receiver.eventsController.close();
    await guest.dispose();
    await server.close();
  });

  test(
    'local handoff and explicit return preserve position without double audio',
    () async {
      await app.load(movie, position: const Duration(seconds: 12));
      await app.togglePlay();
      receiver.beforePlay = () => expect(phone.snapshot.playing, isFalse);
      await app.castTo(cast);
      expect(app.isCasting, isTrue);
      expect(app.target, same(cast));
      expect(cast.snapshot.playing, isTrue);
      expect(phone.snapshot.playing, isFalse);
      receiver.position = 42000;
      receiver.emit();
      await app.returnFromCast();
      expect(app.isCasting, isFalse);
      expect(app.target, same(phone));
      expect(phone.snapshot.position.inSeconds, 42);
      expect(phone.snapshot.playing, isFalse);
      expect(receiver.calls.last, 'disconnect');
      expect(phone.commands.where((command) => command == 'play').length, 1);
      expect(clientsCreated, 0);
    },
  );

  test(
    'same room socket and durable host allowance survive both target changes',
    () async {
      expect(await app.connect(support.ticket), isTrue);
      await app.load(movie, position: const Duration(seconds: 12));
      await app.togglePlay();
      await until(() => !server.roomPaused);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final ticket = app.room;
      expect(store.writes, 1);
      await app.castTo(cast);
      expect(app.isCasting, isTrue);
      expect(app.room, same(ticket));
      expect(client.joins, 1);
      await app.seek(const Duration(seconds: 42));
      await until(() => server.roomPosition.inSeconds >= 42);
      final phonePlays = phone.commands
          .where((command) => command == 'play')
          .length;
      await app.returnFromCast();
      expect(app.isCasting, isFalse);
      expect(app.room, same(ticket));
      expect(app.isConnected, isTrue);
      expect(clientsCreated, 1);
      expect(client.joins, 1);
      expect(phone.snapshot.playing, isFalse);
      expect(phone.snapshot.position.inSeconds, 42);
      expect(
        phone.commands.where((command) => command == 'play').length,
        phonePlays,
      );
      await until(() => server.roomPaused);
      expect(store.writes, 1);
      expect(await quota.remainingFreeHostsToday(), 0);

      // A failed second handoff must leave the rebound phone bridge usable.
      await app.togglePlay();
      await until(() => !server.roomPaused);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final rejectedReceiver = _Receiver()..fail = 'load';
      final rejected = CastPlaybackTarget(transport: rejectedReceiver);
      try {
        await app.castTo(rejected);
        expect(app.isCasting, isFalse);
        expect(phone.snapshot.playing, isTrue);
        expect(client.joins, 1);
        expect(store.writes, 1);
      } finally {
        await rejected.close();
        await rejectedReceiver.eventsController.close();
      }
    },
  );

  test('failed receiver load rolls back accepted phone playback', () async {
    await app.load(movie);
    await app.togglePlay();
    receiver.fail = 'load';
    await app.castTo(cast);
    expect(app.isCasting, isFalse);
    expect(app.target, same(phone));
    expect(phone.snapshot.playing, isTrue);
    expect(receiver.calls, contains('disconnect'));
    expect(app.message, contains('phone session is still open'));
  });

  test('failed return keeps receiver selected and phone silent', () async {
    await app.load(movie);
    await app.togglePlay();
    await app.castTo(cast);
    phone.throwSeek = true;
    await app.returnFromCast();
    expect(app.isCasting, isTrue);
    expect(phone.snapshot.playing, isFalse);
    expect(app.message, contains('Could not return'));
    await app.togglePlay();
    expect(cast.snapshot.playing, isTrue);
  });

  test(
    'same receiver resume restores effective room play and seek on user command',
    () async {
      expect(await app.connect(support.ticket), isTrue);
      await app.load(movie);
      await app.castTo(cast);
      receiver.session = 'suspended';
      receiver.emit();
      receiver.session = 'connected';
      receiver.position = 8000;
      receiver.emit();
      expect(phone.snapshot.playing, isFalse);
      await app.togglePlay();
      await until(() => !server.roomPaused);
      expect(cast.snapshot.playing, isTrue);
      await app.seek(const Duration(seconds: 22));
      await until(() => server.roomPosition.inSeconds >= 22);
      expect(receiver.position, 22000);
      expect(client.joins, 1);
      expect(store.writes, 1);
    },
  );

  test(
    'invalid receiver media returns to last accepted position paused',
    () async {
      await app.load(movie);
      await app.castTo(cast);
      receiver.position = 42000;
      receiver.emit();
      receiver.token = 'another-senders-media';
      receiver.emit();
      expect(cast.snapshot.ready, isFalse);
      expect(cast.snapshot.position, Duration.zero);
      await app.returnFromCast();
      expect(app.isCasting, isFalse);
      expect(phone.snapshot.media?.uri, movie.uri);
      expect(phone.snapshot.position.inSeconds, 42);
      expect(phone.snapshot.playing, isFalse);
    },
  );

  test(
    'receiver initiated play authorizes and consumes the hosted session once',
    () async {
      expect(await app.connect(support.ticket), isTrue);
      await app.load(movie);
      await app.castTo(cast);
      expect(store.writes, 0);
      receiver.player = 'playing';
      receiver.emit();
      await until(() => !server.roomPaused);
      expect(store.writes, 1);
      expect(cast.snapshot.playing, isTrue);
      receiver.player = 'paused';
      receiver.emit();
      await until(() => server.roomPaused);
      receiver.player = 'playing';
      receiver.emit();
      await until(() => !server.roomPaused);
      expect(store.writes, 1);
    },
  );

  test(
    'denied receiver initiated play pauses before any room play announcement',
    () async {
      expect(await app.connect(support.ticket), isTrue);
      await app.load(movie);
      await app.castTo(cast);
      await quota.recordSessionStarted(
        sessionId: 'earlier-host',
        isCreator: true,
        peerCount: 1,
        synchronizedPlaybackActive: true,
      );
      receiver.player = 'playing';
      receiver.emit();
      await until(() => app.needsPlus);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(receiver.player, 'paused');
      expect(server.roomPaused, isTrue);
      expect(server.acceptedChanges.every((change) => change.paused), isTrue);
      expect(store.writes, 1);
    },
  );

  test(
    'a delayed earlier load cannot overwrite the source accepted for Cast',
    () async {
      await app.load(movie);
      final gate = repository.gate = Completer<void>();
      final loading = app.load(
        MediaItem.fromUrl('https://media.example.com/other.mp4'),
      );
      final switching = app.castTo(cast);
      gate.complete();
      await Future.wait([loading, switching]);
      expect(app.isCasting, isTrue);
      expect(cast.snapshot.media?.uri, movie.uri);
      expect(phone.snapshot.media?.uri, movie.uri);
    },
  );

  test(
    'leaving during chooser cannot accept a late receiver or resume phone',
    () async {
      await app.load(movie);
      final gate = receiver.connectGate = Completer<void>();
      final switching = app.castTo(cast);
      await until(() => receiver.calls.contains('connect'));
      await app.leavePlayer();
      gate.complete();
      await switching;
      expect(app.isCasting, isFalse);
      expect(app.inPlayer, isFalse);
      expect(phone.snapshot.playing, isFalse);
      expect(receiver.calls, isNot(contains('load')));
    },
  );

  test(
    'unexpected receiver loss keeps explicit recovery and never auto plays phone',
    () async {
      await app.load(movie);
      await app.togglePlay();
      await app.castTo(cast);
      receiver.position = 33000;
      receiver.emit();
      receiver.session = 'disconnected';
      receiver.emit();
      await Future<void>.delayed(Duration.zero);
      expect(app.isCasting, isTrue);
      expect(phone.snapshot.playing, isFalse);
      expect(app.message, contains('disconnected'));
      await app.returnFromCast();
      expect(app.isCasting, isFalse);
      expect(phone.snapshot.position.inSeconds, 33);
      expect(phone.snapshot.playing, isFalse);
    },
  );

  test(
    'unsupported media is rejected before connecting or pausing phone',
    () async {
      await app.load(
        MediaItem(uri: Uri.parse('file:///movie.mp4'), title: 'Local'),
      );
      await app.togglePlay();
      await app.castTo(cast);
      expect(app.isCasting, isFalse);
      expect(phone.snapshot.playing, isTrue);
      expect(receiver.calls, isNot(contains('connect')));
      expect(app.message, CastPlaybackTarget.unsupportedMessage);
    },
  );
}

Future<void> until(bool Function() condition) async {
  final timeout = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(timeout)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
