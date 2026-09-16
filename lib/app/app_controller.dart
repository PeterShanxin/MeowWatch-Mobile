import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:nearby_bridge/nearby_bridge.dart' show NearbyFrame;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/billing/billing_service.dart';
import '../core/billing/hosting_access_policy.dart';
import '../core/chat/chat_store.dart';
import '../core/connect/room_code.dart';
import '../core/connect/room_config.dart';
import '../core/connect/username_generator.dart';
import '../core/media/media_item.dart';
import '../core/nearby/nearby_desktop_target.dart';
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
  NearbyDesktopTarget? _nearby;
  _PhoneResume? _phoneResume;
  StreamSubscription<NearbyFrame>? _nearbySocial;
  List<ChatMessage> _nearbyMessages = const [];
  String? _nearbyEpoch;

  bool get isNearby => _nearby != null;
  NearbyDesktopTarget? get nearby => _nearby;
  PlaybackTarget get target => _nearby ?? phone;
  bool get isConnected =>
      (!isNearby || _nearby!.connected) &&
      connection.status == SyncConnectionStatus.connected;
  bool get isLocal => room == null;
  List<ChatMessage> get messages =>
      isNearby ? _nearbyMessages : _chat?.messages ?? const [];
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
    final chosen = trimmed.isEmpty
        ? generateUsername()
        : trimmed.characters.take(24).toString();
    if (!isNearby) username = chosen;
    repository.displayName = chosen;
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

  static bool _sameRoom(RoomConfig? left, RoomConfig? right) =>
      left != null &&
      right != null &&
      left.server == right.server &&
      left.port == right.port &&
      left.room == right.room;

  /// The caller has already paired, authenticated and accepted a full snapshot.
  /// Ownership transfers here; a rejected candidate is closed without commands.
  Future<bool> adoptNearby(NearbyDesktopTarget desktop) async {
    if (identical(_nearby, desktop)) return desktop.connected;
    if (busy || _closed) {
      await desktop.close();
      return false;
    }
    final accepted = desktop.remote;
    if (!desktop.connected || accepted == null) {
      await desktop.close();
      report('Reconnect to the desktop before choosing it.');
      return false;
    }
    if (room != null && !_sameRoom(room!.config, accepted.room)) {
      await desktop.close();
      report('Join this exact room on your desktop first, then try again.');
      return false;
    }
    busy = true;
    var generation = _connectGeneration;
    var handedOff = false;
    _changed();
    try {
      await saveProgress();
      _requireCurrent(generation);
      final resume = isNearby
          ? _phoneResume!
          : _PhoneResume(
              room: room,
              mediaRoom: _mediaRoom,
              username: username,
              playback: phone.snapshot,
            );
      await phone.pause();
      _requireCurrent(generation);
      if (!desktop.connected || desktop.remote?.epoch != accepted.epoch) {
        throw const _NearbyHandoffFailed();
      }
      // Invalidate phone callbacks only after preparation succeeded. A storage
      // failure above must leave the original live phone session subscribed.
      generation = ++_connectGeneration;
      ++_mediaGeneration;
      _phoneResume = resume;
      handedOff = true;
      if (isNearby) {
        await _detachNearby();
        _requireCurrent(generation);
      }
      await _detachRoom();
      _requireCurrent(generation);
      await phone.pause();
      _requireCurrent(generation);
      _nearby = desktop;
      desktop.addListener(_applyNearby);
      _nearbySocial = desktop.social.listen(_onNearbySocial);
      inPlayer = true;
      needsPlus = false;
      _applyNearby();
      if (!desktop.connected || desktop.remote?.epoch != accepted.epoch) {
        desktop.client.disconnect();
        _applyNearby();
        report('Desktop connection changed. Reconnect or watch on this phone.');
        return false;
      }
      return true;
    } catch (_) {
      if (_current(generation)) {
        if (handedOff) {
          // Keep explicit recovery available; never silently create a second
          // Syncplay participant after the phone socket has been disposed.
          _nearby = desktop;
          desktop.addListener(_applyNearby);
          _nearbySocial ??= desktop.social.listen(_onNearbySocial);
          desktop.client.disconnect();
          inPlayer = true;
          _applyNearby();
          report('Could not finish switching. Choose Watch on this phone.');
        } else {
          report('Could not switch devices. Your phone session is still open.');
        }
      }
      return false;
    } finally {
      if (!identical(_nearby, desktop)) await desktop.close();
      busy = false;
      _changed();
    }
  }

  void _applyNearby() {
    final desktop = _nearby;
    if (_closed || desktop == null) return;
    final snapshot = desktop.remote;
    peers.clear();
    peerFiles.clear();
    if (!desktop.connected || snapshot == null) {
      connection = const SyncConnectionState(
        status: SyncConnectionStatus.disconnected,
      );
      typing.clear();
      reaction = null;
      _nearbyMessages = const [];
      _changed();
      return;
    }
    final saved = _phoneResume?.room;
    if (_nearbyEpoch != snapshot.epoch) {
      _nearbyEpoch = snapshot.epoch;
      typing.clear();
      reaction = null;
    }
    final remoteRoom = snapshot.room;
    room = remoteRoom == null
        ? null
        : RoomTicket(
            id: _sameRoom(saved?.config, remoteRoom)
                ? saved!.id
                : 'nearby:${snapshot.desktopId}:${snapshot.epoch}',
            config: remoteRoom,
            isHost: _sameRoom(saved?.config, remoteRoom) && saved!.isHost,
          );
    username = snapshot.username;
    connection = SyncConnectionState(
      status: snapshot.connection,
      username: snapshot.username,
    );
    if (isConnected) peers.addAll(snapshot.participants);
    if (!isConnected) {
      typing.clear();
      reaction = null;
    }
    _nearbyMessages = snapshot.messages;
    _changed();
  }

  void _onNearbySocial(NearbyFrame frame) {
    final desktop = _nearby;
    if (_closed ||
        desktop == null ||
        !desktop.connected ||
        !isConnected ||
        frame.fields['sessionEpoch'] != desktop.remote?.epoch) {
      return;
    }
    final event = frame.fields['event'];
    if (event is! Map<String, Object?>) return;
    final name = event['username'];
    if (name is! String || name.isEmpty || name.length > 150) return;
    switch (frame.type) {
      case 'chat.message':
        final text = event['text'];
        final timestamp = event['receivedAtUnixMs'];
        if (text is! String ||
            text.length > 4096 ||
            timestamp is! int ||
            timestamp < 0 ||
            timestamp > 8640000000000000 ||
            event['system'] is! bool ||
            event['isMine'] is! bool) {
          return;
        }
        final message = ChatMessage(
          username: name,
          text: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
          system: event['system']! as bool,
          isMine: event['isMine']! as bool,
        );
        if (!_nearbyMessages.contains(message)) {
          final updated = [..._nearbyMessages, message];
          _nearbyMessages = List.unmodifiable(
            updated.skip(updated.length > 100 ? updated.length - 100 : 0),
          );
        }
      case 'chat.reaction':
        final emoji = event['reaction'];
        if (emoji is! String || emoji.isEmpty || emoji.length > 16) return;
        reaction = ReactionEvent(username: name, emoji: emoji);
        _reactionTimer?.cancel();
        _reactionTimer = Timer(const Duration(seconds: 3), () {
          reaction = null;
          _changed();
        });
      case 'chat.typing':
        if (event['typing'] is! bool) return;
        if (event['typing'] == true) {
          if (typing.length < 256 || typing.containsKey(name)) {
            typing[name] = DateTime.now();
          }
        } else {
          typing.remove(name);
        }
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 4), () {
          typing.clear();
          _changed();
        });
      case 'presence':
        if (event['kind'] == 'joined' &&
            name != username &&
            peers.length < 256) {
          peers.add(name);
        }
        if (event['kind'] == 'left') {
          peers.remove(name);
          typing.remove(name);
        }
    }
    _changed();
  }

  Future<void> _detachNearby() async {
    final desktop = _nearby;
    final social = _nearbySocial;
    _nearby = null;
    _nearbySocial = null;
    desktop?.removeListener(_applyNearby);
    if (desktop != null) {
      room = null;
      username = _phoneResume?.username ?? repository.displayName ?? username;
      _mediaRoom = _phoneResume?.mediaRoom;
    }
    _nearbyMessages = const [];
    _nearbyEpoch = null;
    peers.clear();
    typing.clear();
    peerFiles.clear();
    reaction = null;
    connection = const SyncConnectionState(
      status: SyncConnectionStatus.disconnected,
    );
    try {
      await social?.cancel();
    } finally {
      await desktop?.close();
    }
  }

  Future<bool> watchOnPhone() async {
    if (!isNearby || busy || _closed) return false;
    busy = true;
    final generation = ++_connectGeneration;
    final saved = _phoneResume;
    _changed();
    try {
      await _detachNearby();
      _requireCurrent(generation);
      room = null;
      username = saved?.username ?? repository.displayName ?? username;
      _mediaRoom = saved?.mediaRoom;
      if (saved?.playback.media != null && saved!.playback.ready) {
        await phone.seek(saved.playback.position);
        _requireCurrent(generation);
      }
      _phoneResume = null;
      needsPlus = false;
      inPlayer = true;
      busy = false;
      // connect claims busy synchronously; there is no unguarded async gap.
      if (saved?.room != null) return await connect(saved!.room!);
      return true;
    } catch (_) {
      if (_current(generation)) {
        room = null;
        report('Could not restore the phone session. Open it from history.');
      }
      return false;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _nearbyCommand(
    Future<void> Function(NearbyDesktopTarget) command, {
    bool play = false,
  }) async {
    final desktop = _nearby;
    final generation = _connectGeneration;
    final epoch = desktop?.remote?.epoch;
    if (busy || _closed || desktop == null || !desktop.connected) {
      report('Reconnect to the desktop or choose Watch on this phone.');
      return;
    }
    if (room != null && !isConnected) {
      report('Wait for your desktop to reconnect to the room.');
      return;
    }
    try {
      final current = room;
      if (play && current?.isHost == true) {
        final result = await hosting.recordSessionStarted(
          sessionId: current!.id,
          isCreator: true,
          peerCount: peers.length,
          synchronizedPlaybackActive: true,
        );
        if (!_current(generation) ||
            !identical(_nearby, desktop) ||
            !desktop.connected ||
            desktop.remote?.epoch != epoch) {
          return;
        }
        if (!result.allowed) {
          needsPlus = true;
          _changed();
          return;
        }
      }
      if (!_current(generation) ||
          !identical(_nearby, desktop) ||
          !desktop.connected ||
          desktop.remote?.epoch != epoch) {
        return;
      }
      await command(desktop);
    } catch (_) {
      if (_current(generation) && identical(_nearby, desktop)) {
        report(
          'Desktop did not confirm that action. Check it before retrying.',
        );
      }
    }
  }

  bool _current(int generation) => !_closed && generation == _connectGeneration;
  void _requireCurrent(int generation) {
    if (!_current(generation)) throw const _ConnectionCancelled();
  }

  Future<bool> _runConnect(
    RoomTicket Function() makeTicket, {
    bool adoptExistingSource = true,
  }) async {
    if (busy || _closed) return false;
    if (isNearby) {
      report('Choose Watch on this phone before joining another room.');
      return false;
    }
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
    if (isNearby) {
      report(
        'Choose this video on your desktop. Phone files are not transferred.',
      );
      return;
    }
    if (busy || _closed) return;
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
    if (isNearby) {
      final playing = target.snapshot.playing;
      await _nearbyCommand(
        (desktop) => playing ? desktop.pause() : desktop.play(),
        play: !playing,
      );
      return;
    }
    if (busy || _closed) return;
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
    if (isNearby) {
      await _nearbyCommand((desktop) => desktop.seek(position));
      return;
    }
    if (busy || _closed) return;
    if (_bridge != null) {
      await _bridge!.seek(position);
    } else {
      await target.seek(position);
    }
    await saveProgress();
  }

  Future<void> resume(WatchHistoryEntry entry) async {
    if (busy || _resumeLoading) return;
    if (isNearby) {
      report('Choose Watch on this phone before opening phone history.');
      return;
    }
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
    final generation = ++_connectGeneration;
    if (isNearby) {
      await _detachNearby();
      if (!_current(generation)) return;
      username = _phoneResume?.username ?? username;
      _phoneResume = null;
    }
    await saveProgress();
    if (!_current(generation)) return;
    await _detachRoom();
    if (!_current(generation)) return;
    room = null;
    _mediaRoom = null;
    inPlayer = true;
    _changed();
  }

  Future<void> leavePlayer() async {
    final generation = ++_connectGeneration;
    ++_mediaGeneration;
    if (isNearby) {
      await _detachNearby();
      if (!_current(generation)) return;
      username = _phoneResume?.username ?? username;
      _phoneResume = null;
    }
    await saveProgress();
    if (!_current(generation)) return;
    await target.pause();
    if (!_current(generation)) return;
    await _detachRoom();
    if (!_current(generation)) return;
    room = null;
    inPlayer = false;
    _changed();
  }

  Future<void> background() async {
    if (busy) ++_connectGeneration;
    if (isNearby) {
      // Releasing the companion lease never pauses or leaves the desktop room.
      ++_connectGeneration;
      _nearby!.client.disconnect();
      _applyNearby();
      return;
    }
    if (_bridge != null) {
      await _bridge!.pause();
    } else {
      await target.pause();
    }
    await saveProgress();
  }

  Future<void> saveProgress() async {
    if (isNearby) return;
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
    if (isNearby) {
      unawaited(_nearbyCommand((desktop) => desktop.sendChat(value)));
      return;
    }
    _chat?.send(value);
  }

  void sendReaction(String emoji) {
    if (!isConnected) {
      report('Reconnect to send a reaction.');
      return;
    }
    if (isNearby) {
      unawaited(_nearbyCommand((desktop) => desktop.sendReaction(emoji)));
      return;
    }
    _chat?.sendReaction(emoji);
  }

  void sendTyping(bool active) {
    if (isNearby) {
      if (isConnected) {
        unawaited(_nearbyCommand((desktop) => desktop.sendTyping(active)));
      }
      return;
    }
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
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    _bridge = null;
    _chat = null;
    _sync = null;
    peers.clear();
    typing.clear();
    peerFiles.clear();
    connection = const SyncConnectionState(
      status: SyncConnectionStatus.disconnected,
    );
    // Capture ownership before awaiting; cancellation must never remove a
    // newer session's listeners if leave and a fresh connect overlap.
    try {
      await bridge?.dispose();
    } finally {
      try {
        await Future.wait(subscriptions.map((item) => item.cancel()));
      } finally {
        try {
          await chat?.dispose();
        } finally {
          await sync?.dispose();
        }
      }
    }
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
        try {
          await _detachNearby();
        } finally {
          await _detachRoom();
        }
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

class _NearbyHandoffFailed implements Exception {
  const _NearbyHandoffFailed();
}

class _PhoneResume {
  const _PhoneResume({
    required this.room,
    required this.mediaRoom,
    required this.username,
    required this.playback,
  });
  final RoomTicket? room;
  final RoomTicket? mediaRoom;
  final String username;
  final PlaybackSnapshot playback;
}
