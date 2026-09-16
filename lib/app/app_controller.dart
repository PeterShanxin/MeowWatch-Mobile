import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/billing/billing_service.dart';
import '../core/billing/hosting_access_policy.dart';
import '../core/chat/chat_store.dart';
import '../core/connect/room_code.dart';
import '../core/connect/room_config.dart';
import '../core/connect/username_generator.dart';
import '../core/media/media_item.dart';
import '../core/playback/playback_target.dart';
import '../core/session/playback_sync_bridge.dart';
import '../core/session/room_invite.dart';
import '../core/sync/endpoint_discovery.dart';
import '../core/sync/endpoint_settings.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/syncplay_client.dart';
import '../core/sync/syncplay_constants.dart';
import '../core/sync/syncplay_endpoints.dart';
import '../data/app_repository.dart';

class PreferenceEndpointSettings implements EndpointSettings {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<String?> get(String key) => _preferences.getString(key);
  @override
  Future<void> set(String key, String value) =>
      _preferences.setString(key, value);
}

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.billing,
    required this.hosting,
    required this.phone,
    EndpointSettings? endpointSettings,
    SyncplayClient Function()? createSyncClient,
  }) : _endpointSettings = endpointSettings ?? PreferenceEndpointSettings(),
       _createSyncClient = createSyncClient ?? SyncplayClient.new {
    username = repository.displayName ?? generateUsername();
    phone.addListener(_onPlayback);
    billing.addListener(_changed);
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!inPlayer) return;
      unawaited(
        saveProgress().catchError((Object _) {
          report(
            'Could not save your progress. Check that your device has free storage.',
          );
        }),
      );
    });
  }

  final AppRepository repository;
  final BillingService billing;
  final HostingAccessPolicy hosting;
  final PlaybackTarget phone;
  final SyncplayClient Function() _createSyncClient;
  final EndpointSettings _endpointSettings;
  late String username;
  RoomTicket? room;
  RoomTicket? _mediaRoom;
  SyncplayClient? _sync;
  PlaybackSyncBridge? _bridge;
  ChatStore? _chat;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> peers = {};
  final Map<String, DateTime> typing = {};
  final Map<String, PeerFile> peerFiles = {};
  SyncConnectionState connection = const SyncConnectionState(
    status: SyncConnectionStatus.disconnected,
  );
  ReactionEvent? reaction;
  Timer? _reactionTimer;
  Timer? _typingTimer;
  late final Timer _historyTimer;
  String? message;
  bool busy = false;
  bool needsPlus = false;
  bool inPlayer = false;
  bool _closed = false;
  Future<void>? _closing;
  int _connectGeneration = 0;
  int _mediaGeneration = 0;
  bool _resumeLoading = false;

  PlaybackTarget get target => phone;
  bool get isConnected => connection.status == SyncConnectionStatus.connected;
  bool get isLocal => room == null;
  List<ChatMessage> get messages => _chat?.messages ?? const [];
  bool get firstLaunch => repository.displayName == null;
  Uri? get invite => room == null ? null : encodeRoomInvite(room!.config);

  void _changed() {
    if (!_closed) notifyListeners();
  }

  void report(String value) {
    message = value;
    _changed();
  }

  void dismissMessage() {
    message = null;
    _changed();
  }

  void dismissPaywall() {
    needsPlus = false;
    _changed();
  }

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    username = trimmed.isEmpty
        ? generateUsername()
        : trimmed.characters.take(24).toString();
    repository.displayName = username;
    await repository.save();
    _changed();
  }

  static String _sessionId() =>
      base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));

  Future<bool> createRoom() => _runConnect(
    () => RoomTicket(
      id: _sessionId(),
      isHost: true,
      config: RoomConfig(
        server: SyncplayConstants.defaultServer,
        port: SyncplayConstants.publicServerPort,
        room: generateRoomCode(),
        username: username,
        endpointPolicy: SyncplayEndpointPolicy.discover,
      ),
    ),
  );

  Future<bool> joinRoom(String input) => _runConnect(() {
    final config = parseRoomInvite(input, username);
    final saved = repository.activeRoom;
    final matching =
        saved != null &&
        saved.config.server == config.server &&
        saved.config.port == config.port &&
        saved.config.room == config.room;
    return RoomTicket(
      id: matching ? saved.id : _sessionId(),
      config: config,
      isHost: matching && saved.isHost,
    );
  });

  Future<bool> connect(RoomTicket ticket, {bool adoptExistingSource = true}) =>
      _runConnect(() => ticket, adoptExistingSource: adoptExistingSource);

  bool _current(int generation) => !_closed && generation == _connectGeneration;
  void _requireCurrent(int generation) {
    if (!_current(generation)) throw const _ConnectionCancelled();
  }

  Future<bool> _runConnect(
    RoomTicket Function() makeTicket, {
    bool adoptExistingSource = true,
  }) async {
    if (busy || _closed) return false;
    // Claim ownership before the first asynchronous quota or disk operation.
    busy = true;
    message = null;
    final generation = ++_connectGeneration;
    _changed();
    SyncplayClient? ownedClient;
    try {
      final ticket = makeTicket();
      if (ticket.isHost && !await hosting.canHostNow(sessionId: ticket.id)) {
        _requireCurrent(generation);
        needsPlus = true;
        return false;
      }
      _requireCurrent(generation);
      await saveProgress();
      _requireCurrent(generation);
      await target.pause();
      _requireCurrent(generation);
      await _detachRoom();
      _requireCurrent(generation);
      // Persist identity before joining. A crash cannot turn re-entry into a
      // fresh metered session with an unrelated ID.
      repository.activeRoom = ticket;
      await repository.save();
      _requireCurrent(generation);
      room = ticket;
      Future<String?> join(
        SyncplayClient client,
        SyncplayEndpoint endpoint,
      ) async {
        ownedClient = client;
        _requireCurrent(generation);
        await _attachRoom(client, generation);
        _requireCurrent(generation);
        final error = await client.connectUntilJoin(
          server: endpoint.host,
          port: endpoint.port,
          room: ticket.config.room,
          username: username,
          password: ticket.config.password,
        );
        _requireCurrent(generation);
        return error;
      }

      final outcome =
          ticket.config.endpointPolicy == SyncplayEndpointPolicy.pinned
          ? await joinPinnedEndpoint(
              config: ticket.config,
              settings: _endpointSettings,
              createClient: _createSyncClient,
              connectUntilJoin: join,
            )
          : await joinFirstWorkingEndpoint(
              config: ticket.config,
              settings: _endpointSettings,
              createClient: _createSyncClient,
              connectUntilJoin: join,
            );
      if (!_current(generation)) {
        await outcome.join?.client.dispose();
        await outcome.retainedClient?.dispose();
        return false;
      }
      if (outcome.join == null) {
        await _detachRoom();
        room = null;
        report(
          outcome.error ??
              'Could not join. Check your connection and try again.',
        );
        return false;
      }
      final joined = outcome.join!;
      room = RoomTicket(
        id: ticket.id,
        config: joined.config,
        isHost: ticket.isHost,
      );
      repository.activeRoom = room;
      await repository.save();
      _requireCurrent(generation);
      _bridge = PlaybackSyncBridge(
        target: target,
        sync: joined.client,
        authorizePlayback: _authorizePlay,
        onError: (error) {
          if (_current(generation)) {
            report('Playback sync needs attention: $error');
          }
        },
      );
      _bridge!.start();
      if (adoptExistingSource &&
          target.snapshot.ready &&
          target.snapshot.media != null) {
        await _bridge!.adoptOpenSource(target.snapshot.media!.uri.toString());
        _mediaRoom = room;
      }
      _requireCurrent(generation);
      inPlayer = true;
      return true;
    } on _ConnectionCancelled {
      await ownedClient?.dispose();
      return false;
    } catch (error) {
      await ownedClient?.dispose();
      if (_current(generation)) {
        await _detachRoom();
        room = null;
        report(
          error is FormatException
              ? error.message
              : 'Could not start the room. Check your connection and available storage, then try again.',
        );
      }
      return false;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _attachRoom(SyncplayClient client, int generation) async {
    await _cancelSubscriptions();
    await _chat?.dispose();
    _requireCurrent(generation);
    _sync = client;
    peers.clear();
    typing.clear();
    peerFiles.clear();
    _chat = ChatStore(sync: client, initialUsername: username);
    _subscriptions.addAll([
      client.connectionState.listen((state) {
        if (!_current(generation) || _sync != client) return;
        connection = state;
        if (state.username != null) username = state.username!;
        if (state.status != SyncConnectionStatus.connected) {
          peers.clear();
          typing.clear();
        }
        _changed();
      }),
      client.presence.listen((event) {
        if (!_current(generation) || _sync != client) return;
        if (event.username == username) return;
        if (event.kind == PresenceKind.joined) {
          peers.add(event.username);
          if (!event.fromRoster) _chat?.addSystem('${event.username} joined.');
          if (target.snapshot.playing) unawaited(_enforceHosting());
        } else {
          peers.remove(event.username);
          typing.remove(event.username);
          peerFiles.remove(event.username);
          _chat?.addSystem('${event.username} left.');
          if (peers.isEmpty) unawaited(_bridge?.peerLeft());
        }
        _changed();
      }),
      client.initialRoster.listen((names) {
        if (!_current(generation) || _sync != client) return;
        peers.addAll(names.where((name) => name != username));
        if (target.snapshot.playing) unawaited(_enforceHosting());
        _changed();
      }),
      client.peerFile.listen((file) {
        if (!_current(generation) || _sync != client) return;
        peerFiles[file.username] = file;
        _changed();
      }),
      _chat!.stream.listen((_) => _changed()),
      _chat!.reactions.listen((event) {
        reaction = event;
        _reactionTimer?.cancel();
        _reactionTimer = Timer(const Duration(seconds: 3), () {
          reaction = null;
          _changed();
        });
        _changed();
      }),
      _chat!.typing.listen((event) {
        if (event.isTyping) {
          typing[event.username] = DateTime.now();
        } else {
          typing.remove(event.username);
        }
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 4), () {
          typing.clear();
          _changed();
        });
        _changed();
      }),
    ]);
  }

  Future<void> _enforceHosting() async {
    final bridge = _bridge;
    final generation = _connectGeneration;
    try {
      if (!await _authorizePlay() && _current(generation)) {
        await bridge?.pause();
      }
    } catch (_) {
      if (!_current(generation)) return;
      await bridge?.pause();
      report(
        'Could not verify today’s hosting allowance. Try again after checking device storage.',
      );
    }
  }

  Future<bool> _authorizePlay() async {
    final current = room;
    final generation = _connectGeneration;
    if (current == null) return true;
    if (!isConnected) return false;
    final result = await hosting.recordSessionStarted(
      sessionId: current.id,
      isCreator: current.isHost,
      peerCount: peers.length,
      synchronizedPlaybackActive: true,
    );
    if (!_current(generation) || !identical(room, current) || !isConnected) {
      return false;
    }
    if (!result.allowed) {
      needsPlus = true;
      _changed();
    }
    return result.allowed;
  }

  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final mediaGeneration = ++_mediaGeneration;
    await saveProgress();
    message = null;
    inPlayer = true;
    _changed();
    try {
      final startingBridge = _bridge;
      if (startingBridge != null) {
        await startingBridge.load(media, position: position);
      } else {
        await target.load(media, position: position);
      }
      if (_closed || mediaGeneration != _mediaGeneration) return;
      // A room can finish connecting during a native local load. Confirm the
      // accepted source to the current bridge, never leave it source-gated.
      if (_bridge != null &&
          !identical(startingBridge, _bridge) &&
          target.snapshot.ready &&
          target.snapshot.media?.uri == media.uri) {
        await _bridge!.markSourceOpen(media.uri.toString());
      }
      _mediaRoom = room;
      await saveProgress();
    } catch (_) {
      report(
        target.snapshot.error ??
            'Could not load the video. Choose another file or link.',
      );
    }
  }

  Future<void> togglePlay() async {
    if (target.snapshot.playing) {
      if (_bridge != null) {
        await _bridge!.pause();
      } else {
        await target.pause();
      }
    } else {
      if (_bridge != null) {
        await _bridge!.play();
      } else {
        await target.play();
      }
    }
    await saveProgress();
  }

  Future<void> seek(Duration position) async {
    if (_bridge != null) {
      await _bridge!.seek(position);
    } else {
      await target.seek(position);
    }
    await saveProgress();
  }

  Future<void> resume(WatchHistoryEntry entry) async {
    if (busy || _resumeLoading) return;
    _resumeLoading = true;
    try {
      if (entry.room != null) {
        if (!await connect(entry.room!, adoptExistingSource: false)) return;
      } else {
        await useLocalMode();
      }
      await load(entry.media, position: entry.position);
    } finally {
      _resumeLoading = false;
    }
  }

  Future<void> useLocalMode() async {
    ++_connectGeneration;
    await saveProgress();
    await _detachRoom();
    room = null;
    _mediaRoom = null;
    inPlayer = true;
    _changed();
  }

  Future<void> leavePlayer() async {
    ++_connectGeneration;
    ++_mediaGeneration;
    await saveProgress();
    await target.pause();
    await _detachRoom();
    room = null;
    inPlayer = false;
    _changed();
  }

  Future<void> background() async {
    if (_bridge != null) {
      await _bridge!.pause();
    } else {
      await target.pause();
    }
    await saveProgress();
  }

  Future<void> saveProgress() async {
    final state = target.snapshot;
    if (!state.ready || state.media == null) return;
    await repository.record(
      WatchHistoryEntry(
        media: state.media!,
        position: state.position,
        duration: state.duration,
        updatedAt: DateTime.now(),
        room: _mediaRoom,
      ),
    );
  }

  void sendChat(String value) {
    if (!isConnected) {
      report('Reconnect to send your message.');
      return;
    }
    _chat?.send(value);
  }

  void sendReaction(String emoji) {
    if (!isConnected) {
      report('Reconnect to send a reaction.');
      return;
    }
    _chat?.sendReaction(emoji);
  }

  void sendTyping(bool active) {
    if (isConnected) _chat?.sendTyping(isTyping: active);
  }

  void _onPlayback() => _changed();

  Future<void> _cancelSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _detachRoom() async {
    final bridge = _bridge;
    final chat = _chat;
    final sync = _sync;
    _bridge = null;
    _chat = null;
    _sync = null;
    peers.clear();
    typing.clear();
    peerFiles.clear();
    connection = const SyncConnectionState(
      status: SyncConnectionStatus.disconnected,
    );
    await bridge?.dispose();
    await _cancelSubscriptions();
    await chat?.dispose();
    await sync?.dispose();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    ++_connectGeneration;
    ++_mediaGeneration;
    _closed = true;
    _historyTimer.cancel();
    _reactionTimer?.cancel();
    _typingTimer?.cancel();
    try {
      await saveProgress();
    } finally {
      // A full disk must not keep the socket or native player alive.
      try {
        await _detachRoom();
      } finally {
        phone.removeListener(_onPlayback);
        billing.removeListener(_changed);
        billing.dispose();
        try {
          await phone.close();
        } finally {
          super.dispose();
        }
      }
    }
  }
}

class _ConnectionCancelled implements Exception {
  const _ConnectionCancelled();
}
