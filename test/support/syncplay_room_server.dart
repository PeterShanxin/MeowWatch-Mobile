import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// A loopback Syncplay room server that speaks the real `State` protocol, so
/// two real [SyncplayClient]s (each driving a real `PlaybackSyncBridge`) can be
/// wired together in one test process.
///
/// It models two rules that decide how explicit playback changes propagate:
///
///  1. An explicit `doSeek` or pause change moves the room immediately. Normal
///     heartbeats also update each watcher's position. With
///     [slowestWatcherAnchor] enabled, Syncplay 1.7.5 periodically anchors the
///     room to the slowest watcher and changes `setBy` without a user command.
///     The option defaults off to preserve older focused protocol tests.
///  2. **The `ignoringOnTheFly` handshake.** A forced update carries
///     `{server: n}`; that watcher's states are ignored until it echoes `n`
///     back, so its pre-apply position can't bounce the room backwards. A
///     client-signalled change carries `{client: n}`, which the server echoes so
///     the client can stop ignoring the room again.
///
/// TLS and the Hello/Set/List handshake are out of scope: clients are attached
/// with [SyncplayClient.debugAttachLoggedInSocket] and fed by [dial].
class SyncplayRoomServer {
  SyncplayRoomServer._(
    this._socket, {
    required this.slowestWatcherAnchor,
    required DateTime Function() clock,
  }) : _clock = clock,
       _setAt = clock();

  static Future<SyncplayRoomServer> start({
    Duration? heartbeat = const Duration(milliseconds: 20),
    bool slowestWatcherAnchor = false,
    DateTime Function()? clock,
  }) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = SyncplayRoomServer._(
      socket,
      slowestWatcherAnchor: slowestWatcherAnchor,
      clock: clock ?? DateTime.now,
    );
    socket.listen(server._accept);
    if (heartbeat != null) {
      server._timer = Timer.periodic(heartbeat, (_) => server.sendHeartbeat());
    }
    return server;
  }

  final ServerSocket _socket;
  final bool slowestWatcherAnchor;
  final DateTime Function() _clock;
  Timer? _timer;
  final List<_Watcher> _watchers = <_Watcher>[];
  final List<Socket> _pending = <Socket>[];

  // The room's authoritative playstate.
  Duration _position = Duration.zero;
  bool _paused = true;
  String? _setBy;
  DateTime _setAt;

  int get port => _socket.port;

  /// The room's live position (advancing while the room is playing).
  Duration get roomPosition =>
      _paused ? _position : _position + _clock().difference(_setAt);

  bool get roomPaused => _paused;
  String? get roomSetBy => _setBy;
  bool hasAnnouncedFile(String name) =>
      _watchers.any((watcher) => watcher.name == name && watcher.hasFile);

  Duration? reportedPosition(String name) {
    for (final watcher in _watchers) {
      if (watcher.name == name) return watcher.position;
    }
    return null;
  }

  bool? reportedPaused(String name) {
    for (final watcher in _watchers) {
      if (watcher.name == name) return watcher.paused;
    }
    return null;
  }

  /// Every state change the room accepted, so a test can assert who drove it.
  final List<({String by, Duration position, bool paused, bool doSeek})>
  acceptedChanges = [];

  /// Connect [client] to this room under [name] and start relaying its traffic.
  Future<void> dial(SyncplayClient client, {required String name}) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _socket.port,
    );
    socket.listen(
      client.debugReceiveChunk,
      onError: (Object _) {},
      cancelOnError: false,
    );
    // A torn-down peer makes the next write fail asynchronously; that is
    // teardown, not a test failure.
    unawaited(socket.done.then((_) {}, onError: (Object _) {}));
    client.debugAttachLoggedInSocket(socket, username: name);
    // Name the watcher the server just accepted (connections arrive in order).
    final watcher = await _claim(name);
    // Bootstrap the client's reply cycle with the current room state.
    _send(watcher);
  }

  Future<_Watcher> _claim(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (_pending.isNotEmpty) {
        final socket = _pending.removeAt(0);
        final watcher = _Watcher(socket, name);
        _watchers.add(watcher);
        socket.listen(
          (chunk) => _onChunk(watcher, chunk),
          onError: (Object _) => _drop(watcher),
          onDone: () => _drop(watcher),
        );
        unawaited(socket.done.then((_) {}, onError: (Object _) {}));
        return watcher;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw StateError('no incoming connection to claim for $name');
  }

  void _accept(Socket socket) => _pending.add(socket);

  void _drop(_Watcher watcher) {
    _watchers.remove(watcher);
    watcher.socket.destroy();
  }

  void _onChunk(_Watcher watcher, List<int> chunk) {
    watcher.buffer += utf8.decode(chunk, allowMalformed: true);
    while (true) {
      final end = watcher.buffer.indexOf('\r\n');
      if (end < 0) break;
      final line = watcher.buffer.substring(0, end);
      watcher.buffer = watcher.buffer.substring(end + 2);
      if (line.trim().isEmpty) continue;
      Object? decoded;
      try {
        decoded = json.decode(line);
      } on FormatException {
        continue;
      }
      if (decoded is Map && decoded['State'] is Map) {
        _onState(watcher, (decoded['State'] as Map).cast<String, Object?>());
      }
      if (decoded is Map &&
          decoded['Set'] is Map &&
          (decoded['Set'] as Map)['file'] is Map) {
        final file = (decoded['Set'] as Map)['file'] as Map;
        watcher.hasFile = file['name'] is String;
      }
      if (decoded is Map && decoded['Chat'] is String) {
        final reply = utf8.encode(
          '${json.encode({
            'Chat': {'username': watcher.name, 'message': decoded['Chat']},
          })}\r\n',
        );
        for (final peer in List<_Watcher>.of(_watchers)) {
          peer.socket.add(reply);
        }
      }
    }
  }

  void _onState(_Watcher watcher, Map<String, Object?> state) {
    var skipPlaystate = false;
    var echoedForcedUpdate = false;
    var carriesOwnChange = false;
    final ignore = state['ignoringOnTheFly'];
    if (ignore is Map) {
      final server = ignore['server'];
      if (server is num &&
          watcher.serverIgnore != 0 &&
          server.toInt() == watcher.serverIgnore) {
        watcher.serverIgnore = 0;
        echoedForcedUpdate = true;
      }
      final client = ignore['client'];
      if (client is num) {
        watcher.pendingClientEcho = client.toInt();
        carriesOwnChange = true;
      }
    }

    final ping = state['ping'];
    if (ping is Map && ping['clientLatencyCalculation'] is num) {
      watcher.clientLatency = (ping['clientLatencyCalculation'] as num)
          .toDouble();
    }

    // A watcher we have forced an update on says nothing about the room until
    // it echoes that update back: its reports still describe the pre-apply
    // world. Two rules keep that from corrupting the room state:
    //
    //  * while the echo is outstanding, drop the watcher's playstate outright;
    //  * the echoing frame itself is only ever a REPLY to the update we forced,
    //    so it cannot move the room either. In flight it can even be overtaken —
    //    another peer's change lands first, and the echo then arrives describing
    //    a world that is already two states old. Accepting it is what makes a
    //    pause bounce straight back to play.
    //
    // The one exception is an echo that also carries the client's own change
    // counter (`ignoringOnTheFly.client`): that is the client saying "this frame
    // contains a deliberate local action I have not had acknowledged", so the
    // user's play/pause/seek rides along instead of being swallowed.
    if (watcher.serverIgnore != 0) skipPlaystate = true;
    if (echoedForcedUpdate && !carriesOwnChange) skipPlaystate = true;

    final playstate = state['playstate'];
    if (!skipPlaystate && playstate is Map) {
      final rawPosition = playstate['position'];
      final paused = playstate['paused'];
      if (rawPosition is num && paused is bool) {
        final position = Duration(
          milliseconds: (rawPosition.toDouble() * 1000).round(),
        );
        final doSeek = playstate['doSeek'] == true;
        final pauseChanged = paused != _paused;
        watcher.position = position;
        watcher.paused = paused;
        watcher.positionAt = _clock();
        if (doSeek || pauseChanged) {
          _position = position;
          _paused = paused;
          _setBy = watcher.name;
          _setAt = _clock();
          acceptedChanges.add((
            by: watcher.name,
            position: position,
            paused: paused,
            doSeek: doSeek,
          ));
          for (final other in _watchers) {
            if (identical(other, watcher)) continue;
            // Monotonic, never reused: an in-flight echo of an OLDER forced
            // update must not be mistaken for the echo of this one.
            other.serverIgnore = ++other.forcedUpdates;
            other.forcedDoSeek = doSeek;
          }
          for (final other in List<_Watcher>.of(_watchers)) {
            _send(other);
          }
          return;
        }
      }
    }

    // Ordinary replies are consumed until the next heartbeat. Replying to
    // every reply creates an unbounded feedback loop unlike the real server.
  }

  /// Send one server heartbeat. Tests can pass `heartbeat: null` and call this
  /// after advancing an injected clock, without waiting for wall time.
  void sendHeartbeat() {
    if (slowestWatcherAnchor) _anchorToSlowestWatcher();
    for (final watcher in List<_Watcher>.of(_watchers)) {
      _send(watcher);
    }
  }

  void _anchorToSlowestWatcher() {
    final now = _clock();
    if (now.difference(_setAt) <= const Duration(seconds: 1)) return;
    final candidates = _watchers.where(
      (watcher) => watcher.hasFile && watcher.position != null,
    );
    if (candidates.isEmpty) return;
    final slowest = candidates.reduce(
      (a, b) =>
          a.positionNow(now, _paused) <= b.positionNow(now, _paused) ? a : b,
    );
    _position = slowest.positionNow(now, _paused);
    _setBy = slowest.name;
    _setAt = now;
  }

  void _send(_Watcher watcher) {
    final playstate = <String, Object?>{
      'position': roomPosition.inMilliseconds / 1000.0,
      'paused': _paused,
      'setBy': _setBy,
    };
    if (watcher.forcedDoSeek) {
      playstate['doSeek'] = true;
      watcher.forcedDoSeek = false;
    }
    final message = <String, Object?>{
      'State': <String, Object?>{
        'playstate': playstate,
        'ping': <String, Object?>{
          'latencyCalculation': DateTime.now().millisecondsSinceEpoch / 1000.0,
          if (watcher.clientLatency != null)
            'clientLatencyCalculation': watcher.clientLatency,
        },
        if (watcher.serverIgnore != 0 || watcher.pendingClientEcho != null)
          'ignoringOnTheFly': <String, Object?>{
            if (watcher.serverIgnore != 0) 'server': watcher.serverIgnore,
            if (watcher.serverIgnore == 0 && watcher.pendingClientEcho != null)
              'client': watcher.pendingClientEcho,
          },
      },
    };
    if (watcher.serverIgnore == 0) watcher.pendingClientEcho = null;
    try {
      watcher.socket.add(utf8.encode('${json.encode(message)}\r\n'));
    } on Object {
      _drop(watcher);
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    for (final watcher in List<_Watcher>.of(_watchers)) {
      watcher.socket.destroy();
    }
    _watchers.clear();
    for (final socket in _pending) {
      socket.destroy();
    }
    _pending.clear();
    await _socket.close();
  }
}

class _Watcher {
  _Watcher(this.socket, this.name);

  final Socket socket;
  final String name;
  String buffer = '';
  bool hasFile = false;
  Duration? position;
  bool? paused;
  DateTime? positionAt;
  Duration positionNow(DateTime now, bool paused) {
    final reported = position!;
    return paused ? reported : reported + now.difference(positionAt!);
  }

  int serverIgnore = 0;
  int? pendingClientEcho;

  /// How many forced updates this watcher has been sent; [serverIgnore] takes
  /// the current value so a counter is never reused and an in-flight echo of an
  /// older update cannot be mistaken for the echo of a newer one.
  int forcedUpdates = 0;

  /// Upstream does **not** set `doSeek` on the first State a newly joined
  /// watcher receives — the official protocol trace has Alice join Bob at
  /// ~309s with `doSeek: false`. A joiner that is merely *behind* the room
  /// therefore never catches up via [decideFollow] (which only corrects when
  /// ahead, or on an explicit seek). MeowWatch's client caches that State and
  /// [PlaybackSyncBridge.markSourceOpen] applies it when the file opens.
  /// Keep this false so Check 6 matches syncplay.pl rather than masking the
  /// miss with a synthetic join seek.
  bool forcedDoSeek = false;
  double? clientLatency;
}
