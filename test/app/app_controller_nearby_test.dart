import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_desktop_target.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_snapshot.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import '../support/sync_playback_fakes.dart';
import 'app_controller_test.dart' as support;

class _Store implements HostingQuotaStore {
  String? value;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    await gate?.future;
    this.value = value;
    writes++;
  }
}

class _Client extends support.ControlledClient {
  Completer<void>? closeGate;
  bool closing = false;
  void roster(List<String> names) => emitInitialRoster(names);
  @override
  Future<void> disposeBackend() async {
    closing = true;
    await closeGate?.future;
    await super.disposeBackend();
  }
}

class _Phone extends SyncTestTarget {
  Completer<void>? pauseGate;
  @override
  Future<void> pause() async {
    await pauseGate?.future;
    await super.pause();
  }
}

class _CredentialStore implements NearbyClientStore {
  @override
  Future<NearbyClientCredential?> read(String desktopId) async => null;
  @override
  Future<void> remove(String desktopId) async {}
  @override
  Future<void> write(NearbyClientCredential credential) async {}
}

// Controller boundary double: transport/authentication have separate tests.
// This models a second accepted participant, never a production fake purchase
// or a claim that a native player or LAN socket has been exercised here.
class _Desktop extends NearbyDesktopTarget {
  // Keep the test's connected flag private behind a named parameter.
  _Desktop({RoomConfig? room, bool connected = true})
    // ignore: prefer_initializing_formals
    : _connected = connected,
      super(
        client: NearbyClient(store: _CredentialStore()),
        credential: NearbyClientCredential(
          desktopId: encodeBytes(List.filled(16, 1)),
          tokenId: encodeBytes(List.filled(16, 2)),
          clientId: encodeBytes(List.filled(16, 3)),
          clientName: 'Test phone',
          endpoint: LanEndpoint(
            address: LanIpv4Address.parse('192.168.1.2'),
            port: 1234,
          ),
          certificateSha256: List.filled(32, 4),
          secret: List.filled(32, 5),
        ),
      ) {
    update(room: room);
    _disconnect = client.states.listen((state) {
      if (state.phase != NearbyClientPhase.connected && !closed) {
        _connected = false;
        notifyListeners();
      }
    });
  }
  late final StreamSubscription<NearbyClientState> _disconnect;
  final _events = StreamController<NearbyFrame>.broadcast(sync: true);
  final commands = <String>[];
  late NearbySnapshot _value;
  bool _connected;
  bool closed = false;
  Completer<void>? closeGate;
  @override
  bool get connected => !closed && _connected;
  @override
  NearbySnapshot get remote => _value;
  @override
  PlaybackSnapshot get snapshot => _value.playback;
  @override
  Stream<NearbyFrame> get social => _events.stream;

  void update({
    RoomConfig? room,
    String epoch = 'epoch-one',
    bool playing = false,
    SyncConnectionStatus connection = SyncConnectionStatus.connected,
    List<ChatMessage> messages = const [],
  }) {
    _value = NearbySnapshot(
      desktopId: credential.desktopId,
      desktopName: 'Desktop',
      epoch: epoch,
      username: 'Desktop watcher',
      connection: connection,
      room: room,
      playback: PlaybackSnapshot(
        media: MediaItem(
          uri: Uri.parse('meowwatch-desktop://opaque/movie'),
          title: 'Desktop movie',
        ),
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 90),
        playing: playing,
        connection: PlaybackConnection.ready,
      ),
      participants: const {'Other watcher'},
      messages: messages,
    );
    notifyListeners();
  }

  void event(String type, Map<String, Object?> body, {String? epoch}) {
    _events.add(
      NearbyFrame({
        'v': 1,
        'type': type,
        'sessionEpoch': epoch ?? remote.epoch,
        'event': body,
      }),
    );
  }

  void disconnect() {
    _connected = false;
    notifyListeners();
  }

  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> seek(Duration position) async => commands.add('seek');
  @override
  Future<void> sendChat(String text) async => commands.add('chat:$text');
  @override
  Future<void> sendReaction(String emoji) async => commands.add('reaction');
  @override
  Future<void> sendTyping(bool active) async => commands.add('typing');
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await closeGate?.future;
    await _disconnect.cancel();
    await _events.close();
    await super.close();
  }
}

void main() {
  late AppController app;
  late support.ControlledRepository repository;
  late _Phone phone;
  late _Store store;
  late LocalHostingAccessPolicy quota;
  late List<_Client> clients;
  late List<_Desktop> desktops;
  setUp(() {
    repository = support.ControlledRepository();
    phone = _Phone();
    store = _Store();
    quota = LocalHostingAccessPolicy(store: store, isPlus: () => false);
    clients = [];
    desktops = [];
    app = AppController(
      repository: repository,
      billing: RevenueCatBillingService(apiKey: ''),
      hosting: quota,
      phone: phone,
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () {
        final client = _Client();
        clients.add(client);
        return client;
      },
    );
  });
  tearDown(() async {
    repository.failWrite = false;
    await app.close();
    for (final desktop in desktops) {
      await desktop.close();
    }
  });
  _Desktop desktop({RoomConfig? room}) {
    final target = _Desktop(room: room);
    desktops.add(target);
    return target;
  }

  Future<void> startPhone() async {
    await app.setName('Phone watcher');
    await app.load(support.media, position: const Duration(seconds: 9));
    expect(await app.connect(support.ticket), isTrue);
  }

  test(
    'mismatched endpoint or room retains usable phone participant',
    () async {
      await startPhone();
      for (final config in [
        const RoomConfig(
          server: 'other',
          port: 8995,
          room: 'room',
          username: 'D',
        ),
        const RoomConfig(
          server: 'syncplay.pl',
          port: 8996,
          room: 'room',
          username: 'D',
        ),
        const RoomConfig(
          server: 'syncplay.pl',
          port: 8995,
          room: 'other',
          username: 'D',
        ),
        null,
      ]) {
        final candidate = desktop(room: config);
        expect(await app.adoptNearby(candidate), isFalse);
        expect(candidate.closed, isTrue);
        expect(clients.single.closed, isFalse);
        expect(app.isConnected, isTrue);
        expect(app.target, same(phone));
        expect(app.message, contains('exact room'));
      }
      await app.togglePlay();
      expect(phone.snapshot.playing, isTrue);
    },
  );

  test(
    'phone disposal completes before desktop controls are enabled',
    () async {
      await startPhone();
      final client = clients.single;
      client.closeGate = Completer<void>();
      final candidate = desktop(room: support.ticket.config);
      final adopting = app.adoptNearby(candidate);
      await support.until(() => client.closing);
      expect(app.busy, isTrue);
      expect(app.isNearby, isFalse);
      await app.togglePlay();
      expect(candidate.commands, isEmpty);
      client.closeGate!.complete();
      expect(await adopting, isTrue);
      expect(client.closed, isTrue);
      expect(phone.snapshot.playing, isFalse);
      expect(app.target, same(candidate));
      expect(app.room!.id, support.ticket.id);
      expect(app.username, 'Desktop watcher');
      expect(app.peers, {'Other watcher'});
      expect(repository.displayName, 'Phone watcher');
      expect(clients, hasLength(1));
    },
  );

  test(
    'same host session is charged once across desktop and phone return',
    () async {
      await startPhone();
      clients.single.roster(['Other watcher']);
      await support.until(() => app.peers.isNotEmpty);
      await app.togglePlay();
      expect(store.writes, 1);
      final ledger = store.value;
      final candidate = desktop(room: support.ticket.config);
      expect(await app.adoptNearby(candidate), isTrue);
      await app.togglePlay();
      expect(candidate.commands, ['play']);
      expect(store.value, ledger);
      expect(store.writes, 1);
      await app.saveProgress();
      expect(
        repository.history.every((entry) => entry.media.uri.scheme == 'https'),
        isTrue,
      );
      expect(await app.watchOnPhone(), isTrue);
      expect(candidate.closed, isTrue);
      expect(candidate.commands, ['play']);
      expect(clients, hasLength(2));
      expect(app.room!.id, support.ticket.id);
      expect(app.username, 'Phone watcher');
      expect(app.target, same(phone));
      expect(phone.snapshot.position, const Duration(seconds: 9));
      clients.last.roster(['Other watcher']);
      await support.until(() => app.peers.isNotEmpty);
      await app.togglePlay();
      expect(store.writes, 1);
    },
  );

  test(
    'existing desktop room is a free guest and original local media returns',
    () async {
      await quota.recordSessionStarted(
        sessionId: 'already-used-today',
        isCreator: true,
        peerCount: 1,
        synchronizedPlaybackActive: true,
      );
      final ledger = store.value;
      await app.setName('My phone');
      await app.load(support.media, position: const Duration(seconds: 12));
      final candidate = desktop(room: support.ticket.config);
      expect(await app.adoptNearby(candidate), isTrue);
      expect(app.room!.isHost, isFalse);
      await app.togglePlay();
      await app.load(MediaItem.fromUrl('https://example.com/another.mp4'));
      expect(candidate.commands, ['play']);
      expect(store.writes, 1);
      expect(store.value, ledger);
      expect(clients, isEmpty);
      expect(await app.watchOnPhone(), isTrue);
      expect(app.isLocal, isTrue);
      expect(app.username, 'My phone');
      expect(phone.snapshot.media!.uri, support.media.uri);
      expect(phone.snapshot.position, const Duration(seconds: 12));
      expect(clients, isEmpty);
    },
  );

  test('snapshot and epoch scoped social events are authoritative', () async {
    final candidate = desktop(room: support.ticket.config);
    expect(await app.adoptNearby(candidate), isTrue);
    candidate.event('chat.message', {
      'username': 'Friend',
      'text': 'Hello',
      'receivedAtUnixMs': 1234,
      'system': false,
      'isMine': false,
    });
    candidate.event('chat.typing', {'username': 'Friend', 'typing': true});
    candidate.event('chat.reaction', {'username': 'Friend', 'reaction': '🐱'});
    expect(app.messages.single.text, 'Hello');
    expect(app.typing.keys, contains('Friend'));
    expect(app.reaction!.emoji, '🐱');
    candidate.event('chat.message', {
      'username': 'Friend',
      'text': 'Stale',
      'receivedAtUnixMs': 1235,
      'system': false,
      'isMine': false,
    }, epoch: 'old');
    expect(app.messages, hasLength(1));
    app.sendChat('Sent');
    await Future<void>.delayed(Duration.zero);
    expect(candidate.commands, contains('chat:Sent'));
    expect(app.messages, hasLength(1));
    candidate.update(
      room: support.ticket.config,
      epoch: 'new',
      messages: [const ChatMessage(username: 'D', text: 'Canonical')],
    );
    expect(app.messages.single.text, 'Canonical');
    expect(app.typing, isEmpty);
    expect(app.reaction, isNull);
    candidate.disconnect();
    expect(app.isConnected, isFalse);
    expect(app.peers, isEmpty);
    expect(app.messages, isEmpty);
    final commands = candidate.commands.length;
    await app.togglePlay();
    app.sendChat('Should not send');
    expect(candidate.commands, hasLength(commands));
  });

  test('history failure before handoff retains phone subscriptions', () async {
    await startPhone();
    repository.failWrite = true;
    final candidate = desktop(room: support.ticket.config);
    expect(await app.adoptNearby(candidate), isFalse);
    expect(candidate.closed, isTrue);
    expect(clients.single.closed, isFalse);
    clients.single.roster(['Still connected']);
    await support.until(() => app.peers.contains('Still connected'));
    expect(app.target, same(phone));
  });

  test(
    'leave cancels pending handoff without resurrecting a desktop',
    () async {
      await startPhone();
      phone.pauseGate = Completer<void>();
      final candidate = desktop(room: support.ticket.config);
      final adopting = app.adoptNearby(candidate);
      await Future<void>.delayed(Duration.zero);
      final leaving = app.leavePlayer();
      phone.pauseGate!.complete();
      await leaving;
      expect(await adopting, isFalse);
      expect(candidate.closed, isTrue);
      expect(app.isNearby, isFalse);
      expect(app.inPlayer, isFalse);
      expect(app.room, isNull);
    },
  );

  test(
    'disconnect during phone disposal leaves explicit recovery only',
    () async {
      await startPhone();
      clients.single.closeGate = Completer<void>();
      final candidate = desktop(room: support.ticket.config);
      final adopting = app.adoptNearby(candidate);
      await support.until(() => clients.single.closing);
      candidate.disconnect();
      clients.single.closeGate!.complete();
      expect(await adopting, isFalse);
      expect(app.isNearby, isTrue);
      expect(app.isConnected, isFalse);
      expect(clients, hasLength(1));
      expect(await app.watchOnPhone(), isTrue);
      expect(clients, hasLength(2));
    },
  );

  test('late quota completion cannot command a detached desktop', () async {
    await startPhone();
    final candidate = desktop(room: support.ticket.config);
    expect(await app.adoptNearby(candidate), isTrue);
    store.gate = Completer<void>();
    final playing = app.togglePlay();
    await Future<void>.delayed(Duration.zero);
    await app.leavePlayer();
    store.gate!.complete();
    await playing;
    expect(candidate.commands, isEmpty);
    expect(app.needsPlus, isFalse);
    expect(app.inPlayer, isFalse);
  });

  test('exhausted host allowance stops remote play before a command', () async {
    await startPhone();
    await quota.recordSessionStarted(
      sessionId: 'another-real-host',
      isCreator: true,
      peerCount: 1,
      synchronizedPlaybackActive: true,
    );
    final candidate = desktop(room: support.ticket.config);
    expect(await app.adoptNearby(candidate), isTrue);
    await app.togglePlay();
    expect(candidate.commands, isEmpty);
    expect(app.needsPlus, isTrue);
    expect(store.writes, 1);
    expect(app.room!.id, support.ticket.id);
  });

  test('late companion cleanup cannot clear a newer phone session', () async {
    await startPhone();
    final candidate = desktop(room: support.ticket.config);
    expect(await app.adoptNearby(candidate), isTrue);
    candidate.closeGate = Completer<void>();
    final leaving = app.leavePlayer();
    await support.until(() => candidate.closed);
    expect(await app.connect(support.ticket), isTrue);
    clients.last.roster(['New participant']);
    await support.until(() => app.peers.contains('New participant'));
    candidate.closeGate!.complete();
    await leaving;
    expect(app.username, 'Phone watcher');
    expect(app.isConnected, isTrue);
    expect(app.inPlayer, isTrue);
    expect(app.peers, contains('New participant'));
    expect(app.room!.id, support.ticket.id);
  });

  test(
    'explicit companion reconnect retains original phone resume identity',
    () async {
      await startPhone();
      final first = desktop(room: support.ticket.config);
      expect(await app.adoptNearby(first), isTrue);
      first.disconnect();
      final replacement = desktop(room: support.ticket.config);
      expect(await app.adoptNearby(replacement), isTrue);
      expect(first.closed, isTrue);
      expect(app.target, same(replacement));
      expect(app.room!.id, support.ticket.id);
      expect(clients, hasLength(1));
      expect(await app.watchOnPhone(), isTrue);
      expect(app.username, 'Phone watcher');
      expect(phone.snapshot.position, const Duration(seconds: 9));
      expect(clients, hasLength(2));
    },
  );

  test(
    'background detaches control without pausing or leaving desktop',
    () async {
      final candidate = desktop(room: support.ticket.config);
      expect(await app.adoptNearby(candidate), isTrue);
      await app.background();
      await Future<void>.delayed(Duration.zero);
      expect(app.isNearby, isTrue);
      expect(app.isConnected, isFalse);
      expect(app.peers, isEmpty);
      expect(candidate.commands, isEmpty);
      expect(clients, isEmpty);
      expect(await app.watchOnPhone(), isTrue);
      expect(candidate.closed, isTrue);
    },
  );
}
