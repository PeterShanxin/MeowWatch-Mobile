import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../chat/chat_signals.dart';
import 'connection_watchdog.dart';
import 'peer_stall_tracker.dart';
import 'peer_state.dart';
import 'ping_service.dart';
import 'sync_activity.dart';
import 'sync_core.dart';
import 'sync_follow.dart';
import 'sync_messages.dart';
import 'syncplay_constants.dart';

/// Upgrades a connected plaintext [Socket] to TLS for [host]. Injectable only
/// so tests can reach the post-handshake branch; see [SyncplayClient].
typedef SecureUpgrade =
    Future<Socket> Function(Socket plain, {required String host});

/// Concrete SyncCore speaking the Syncplay text protocol over a TCP socket
/// upgraded to TLS. One JSON object per line, terminated `\r\n`.
///
/// TLS is mandatory. There is no plaintext mode and no STARTTLS fallback: a
/// server that will not encrypt is a connection error, never a downgrade (#264).
class SyncplayClient extends SyncCore {
  SyncplayClient({
    this.onLog,
    this.shouldLog,
    this.livenessTimeout = const Duration(seconds: 12),
    @visibleForTesting SecureUpgrade? secureUpgrade,
  }) : _secureUpgrade = secureUpgrade ?? _realSecureUpgrade;

  /// Performs the STARTTLS upgrade of an already-connected plaintext socket.
  /// Production is always [_realSecureUpgrade]; the seam exists so the
  /// post-handshake branch can be covered without committing a private key as a
  /// test fixture. The failure branch is covered against the real
  /// [SecureSocket.secure].
  final SecureUpgrade _secureUpgrade;

  static Future<Socket> _realSecureUpgrade(
    Socket plain, {
    required String host,
  }) => SecureSocket.secure(
    plain,
    host: host,
    // Validate the chain and the hostname; never accept a certificate we
    // cannot verify. Rejection throws, and the caller fails the connection
    // closed rather than continuing in the clear (#264).
    onBadCertificate: (_) => false,
  );

  /// Optional debug sink for raw protocol traffic and follow decisions.
  final void Function(String line)? onLog;

  /// Live sink probe for avoiding expensive log formatting when a line will be
  /// dropped. [verboseOnly] distinguishes raw traffic/no-op FOLLOW lines from
  /// meaningful applied decisions and server errors.
  ///
  /// Defaults to enabled when omitted so custom/test sinks retain the original
  /// full-trace behavior. Production passes the process log's current level.
  final bool Function({required bool verboseOnly})? shouldLog;

  bool _shouldFormatLog({required bool verboseOnly}) =>
      onLog != null && (shouldLog?.call(verboseOnly: verboseOnly) ?? true);

  /// How long to tolerate silence from the server before presuming the link is
  /// dead (a half-open TCP that never fired onDone/onError). Generous relative
  /// to the ~1s State heartbeat. Injectable for tests.
  final Duration livenessTimeout;

  /// Requested name before login; server-assigned identity after it.
  String get username => _username;

  /// Secure Hello completed on this connection. Used by public-endpoint
  /// discovery to tell an unreachable candidate (try the next) from a live
  /// server that refused this room (do not hop).
  bool get hasCompletedHello => _everLoggedIn;

  Socket? _socket;
  LineFramer _framer = LineFramer();
  final PingService _ping = PingService();

  late final ConnectionWatchdog _watchdog = ConnectionWatchdog(
    timeout: livenessTimeout,
    onTimeout: _onWatchdogTimeout,
  );

  // Reconnect bookkeeping. Server/port are remembered from the first connect so
  // a dropped link can be re-established without UI involvement.
  String _server = '';
  int _port = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  // Bumped every time we abandon or supersede a connection attempt (new dial,
  // reconnect, manual leave). The TLS negotiation runs async on a socket that
  // isn't yet bound to [_socket]; a slow handshake could otherwise complete
  // *after* its attempt was torn down and bind a zombie socket. Each
  // negotiation captures the generation it started in and bails if it no longer
  // matches.
  int _generation = 0;

  // The name the user asked for. Set once at connect() and NEVER overwritten —
  // every (re)connect Hello requests THIS name. Kept distinct from [_username]
  // (the server-assigned identity) so a server-side dedupe suffix can't feed
  // back into the next Hello and compound ("meow" -> "meow_" -> "meow__" …) on
  // each reconnect against a lingering ghost session (#93).
  String _requestedUsername = '';

  String _username = '';
  String _room = '';
  String? _password;

  /// True when [name] is us — the current server-assigned identity. ONLY the
  /// current assigned name is reliably self: in the reconnect window a name the
  /// server suffixes is indistinguishable between our own lingering ghost and a
  /// real user who grabbed our freed name, so any name-based ghost guess can
  /// erase a genuine peer. A stale ghost may therefore briefly appear as a peer;
  /// the UI keeps peer files keyed by username so that ghost's eventual
  /// departure can't wipe the real friend's file — the actual #93 fix.
  bool _isSelf(String name) => name == _username;

  bool _loggedIn = false;

  /// True only while [_socket] is the TLS socket produced by a completed
  /// handshake. Every outbound frame is gated on it: the Hello carries the room
  /// password, and everything after it carries the file name, chat and watch
  /// position. There is no plaintext mode to fall back to, so this is the one
  /// switch that decides whether the client may speak at all — a structural
  /// backstop so no later rewrite of the negotiation can quietly reintroduce a
  /// plaintext Hello (#264).
  bool _channelSecure = false;

  // Once a Hello completes, later silence means "recover the room connection".
  // Before that, silence means the endpoint itself is bad/stale/unresponsive
  // and should be surfaced as an actionable error instead of looping forever.
  bool _everLoggedIn = false;

  // True once the initial roster greeting has been emitted. Set on the first
  // RosterMessage and never reset — reconnects are silent (issue #90).
  bool _rosterGreeted = false;

  // Latest local playback state for the heartbeat.
  Duration _localPosition = Duration.zero;
  bool _localPaused = true;

  // Tracks whether the peer's player claims `playing` but is not advancing (a
  // frozen engine). Feeds [decideFollow] so we don't rewind to chase a stuck
  // peer — the rewind-sawtooth amplifier (the 2026-06-20 field regression).
  final PeerStallTracker _peerStall = PeerStallTracker();

  // Snapshot of the local state from just before the latest update — lets us
  // classify our OWN play/pause/seek for self-notifications (issue #27).
  Duration _prevLocalPosition = Duration.zero;
  bool _prevLocalPaused = true;

  // ignoringOnTheFly handshake counters.
  int _clientIgnore = 0;
  int _serverIgnore = 0;
  bool _pendingStateChange = false;
  bool _pendingDoSeek = false;

  /// False until we have applied a named-setter room state (or caught up to
  /// one). syncplay.pl does not set `doSeek` on a joiner's first State, so
  /// [decideFollow] would otherwise leave us at 0 forever.
  bool _initialCatchUpDone = false;

  // The most recent server latencyCalculation we must echo back.
  double? _serverLatencyCalculation;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    _server = server;
    _port = port;
    _requestedUsername = username;
    _username = username;
    _room = room;
    _password = password;
    _manualDisconnect = false;
    _everLoggedIn = false;
    _reconnectAttempt = 0;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connecting),
    );
    await _openConnection();
  }

  /// Connect and complete when login succeeds or the attempt ends in a named
  /// error. The lobby uses this so the watch route is only pushed after a
  /// completed join (#265).
  ///
  /// A Hello-then-Error is a failed join: an Error after Connected, while
  /// this method is still listening, wins. [onHandoff] runs after Hello
  /// with that listener still attached so the watch route can subscribe
  /// before the broadcast stream would drop a following Error.
  Future<String?> connectUntilJoin({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
    Future<void> Function()? onHandoff,
  }) async {
    String? terminalError;
    String? failedJoin() {
      if (terminalError != null) return terminalError;
      final last = lastConnectionState;
      if (last != null && last.status == SyncConnectionStatus.error) {
        return (last.message != null && last.message!.isNotEmpty)
            ? last.message
            : 'Couldn\'t connect to room $room';
      }
      return null;
    }

    final firstOutcome = Completer<void>();
    void cancelled() {
      terminalError ??= 'Room connection cancelled.';
      if (!firstOutcome.isCompleted) firstOutcome.complete();
    }

    final sub = connectionState.listen((s) {
      if (s.status == SyncConnectionStatus.connected) {
        if (!firstOutcome.isCompleted) firstOutcome.complete();
      } else if (s.status == SyncConnectionStatus.error) {
        terminalError = (s.message != null && s.message!.isNotEmpty)
            ? s.message
            : 'Couldn\'t connect to room $room';
        if (!firstOutcome.isCompleted) firstOutcome.complete();
      } else if (s.status == SyncConnectionStatus.disconnected) {
        cancelled();
      }
    }, onDone: cancelled);
    try {
      await connect(
        server: server,
        port: port,
        username: username,
        room: room,
        password: password,
      );
      await firstOutcome.future;
      // Same-turn Error after Hello (one chunk, two frames) is applied
      // before the lobby decides the join succeeded. Broadcast delivery
      // is async; lastConnectionState is set when the Error is emitted.
      await Future<void>.delayed(Duration.zero);
      final afterHello = failedJoin();
      if (afterHello != null) return afterHello;
      if (onHandoff != null) await onHandoff();
      return failedJoin();
    } finally {
      await sub.cancel();
    }
  }

  /// Open (or re-open) the socket and start the TLS handshake. Shared by the
  /// initial [connect] and the auto-reconnect path; callers set the surrounding
  /// status (`connecting` vs. `reconnecting`) before invoking.
  Future<void> _openConnection() async {
    // Tear down any prior socket and stale framer state before dialing again.
    _watchdog.stop();
    _socket?.destroy();
    _socket = null;
    _framer = LineFramer();
    _loggedIn = false;
    _channelSecure = false;
    final generation = ++_generation;

    try {
      final plain = await Socket.connect(
        _server,
        _port,
        timeout: const Duration(seconds: 10),
      );
      // A late dial that resolves after we already moved on: drop it.
      if (generation != _generation || _manualDisconnect) {
        plain.destroy();
        return;
      }
      // Track the negotiation socket immediately so a mid-handshake teardown
      // (watchdog trip or manual leave, before _bindSocket runs) can destroy it.
      _socket = plain;
      // Attempt TLS upgrade first (public servers require it).
      _sendRaw(plain, encodeTlsRequest());
      emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
      );
      // Guard the handshake too: if the socket binds but the server never
      // completes the Hello, the watchdog trips and we retry.
      _watchdog.bump();
      _attachPlainForTlsNegotiation(plain, _server, generation);
    } on SocketException catch (e) {
      if (generation != _generation || _manualDisconnect) return;
      onLog?.call('connect failed: ${e.message}');
      if (_everLoggedIn) {
        _scheduleReconnect(message: 'Could not reach server: ${e.message}');
      } else {
        _failInitialConnection();
      }
    }
  }

  void _onWatchdogTimeout() {
    if (_manualDisconnect) return;
    if (!_everLoggedIn) {
      _failInitialSilence();
      return;
    }
    _onConnectionLost();
  }

  /// Presume the current link dead (silent timeout, socket error, or clean
  /// close) and arm a backed-off reconnect — unless the user asked to leave.
  void _onConnectionLost() {
    if (_manualDisconnect) return;
    if (!_everLoggedIn) {
      _failInitialConnection();
      return;
    }
    onLog?.call(
      'connection lost (no server traffic within '
      '${livenessTimeout.inSeconds}s) — reconnecting',
    );
    _scheduleReconnect();
  }

  void _failInitialSilence() {
    if (_manualDisconnect) return;
    final wait = livenessTimeout.inMilliseconds >= 1000
        ? '${livenessTimeout.inSeconds} seconds'
        : '${livenessTimeout.inMilliseconds} milliseconds';
    _failInitialConnection(
      'The Syncplay server at $_server:$_port stayed silent while opening '
      'a secure connection (waited $wait). Check Advanced server/port or '
      'paste your friend\'s full code.',
    );
  }

  void _failInitialConnection([String? message]) {
    if (_manualDisconnect) return;
    message ??=
        'Could not reach Syncplay server $_server:$_port. Check Advanced '
        'server/port or paste your friend\'s full code.';
    onLog?.call('connect failed before login: $message');
    _stopReconnecting();
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    _channelSecure = false;
    emitConnectionState(
      SyncConnectionState(status: SyncConnectionStatus.error, message: message),
    );
  }

  /// Permanently stop the connection — no auto-reconnect. Used for a deliberate
  /// leave and for a fatal server protocol error (rejected room/password). Bumps
  /// the generation so a trailing onDone from the closing socket is ignored.
  void _stopReconnecting() {
    _manualDisconnect = true;
    _generation++;
    _watchdog.stop();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect({String? message}) {
    if (_manualDisconnect) return;
    _watchdog.stop();
    // Invalidate any in-flight handshake from the attempt we're abandoning.
    _generation++;
    // Clear _socket BEFORE destroying so the destroyed socket's trailing
    // onDone/onError can't observe itself as the live socket.
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    _channelSecure = false;
    // Surface the gap to the UI so playback auto-pauses while we recover.
    emitConnectionState(
      SyncConnectionState(
        status: SyncConnectionStatus.reconnecting,
        message: message,
      ),
    );
    _reconnectTimer?.cancel();
    final delay = reconnectBackoff(attempt: _reconnectAttempt);
    _reconnectAttempt++;
    // Mark the otherwise-silent gap between "connection lost" and the next
    // `>> Hello` so a stalled recovery is visible in the log (#156). Neat-kept.
    onLog?.call(
      'reconnect: attempt $_reconnectAttempt in ${delay.inMilliseconds}ms',
    );
    _reconnectTimer = Timer(delay, () {
      if (_manualDisconnect) return;
      unawaited(_openConnection());
    });
  }

  /// Listen on the plain socket only long enough to receive the TLS answer,
  /// then upgrade to a SecureSocket and attach the main listener.
  ///
  /// STARTTLS is mandatory (#264). MeowWatch has no plaintext mode, so every
  /// outcome other than a completed handshake ends the attempt — the Hello that
  /// would follow carries the username, the room name and the room password,
  /// and `Set`/`Chat`/`State` after it carry the file name, the chat and the
  /// watch position. A server that will not encrypt is refused by name rather
  /// than downgraded to, so an on-path attacker cannot strip the upgrade by
  /// answering "no".
  ///
  /// The subscription is *paused* (not cancelled) before the handshake: a
  /// `dart:io` [Socket] is single-subscription and cannot be listened to again
  /// after a cancel, and pausing leaves the bytes buffered for
  /// [SecureSocket.secure] to consume.
  void _attachPlainForTlsNegotiation(
    Socket plain,
    String server,
    int generation,
  ) {
    // True once this attempt is superseded (reconnect/manual leave) or done —
    // every completion path must bail rather than bind a zombie socket.
    bool stale() => generation != _generation || _manualDisconnect;
    // Latched by the first outcome (upgrade or refusal); later bytes and the
    // socket's own close events are then irrelevant to this attempt.
    var settled = false;
    late StreamSubscription<Uint8List> sub;
    sub = plain.listen(
      (chunk) async {
        if (settled) return;
        final List<String> lines;
        try {
          lines = _framer.addChunk(chunk);
        } on LineOverflowException catch (e) {
          settled = true;
          if (stale()) return;
          _failTlsNegotiation('malformed STARTTLS answer: $e');
          return;
        } on FormatException catch (e) {
          // utf8.decode throws here. An uncaught throw from this async
          // onData never reaches onError, so fail closed by name.
          settled = true;
          if (stale()) return;
          _failTlsNegotiation('malformed STARTTLS answer: $e');
          return;
        }
        for (final line in lines) {
          if (line.isEmpty) continue;
          final ServerMessage decoded;
          try {
            decoded = decodeServerMessage(
              json.decode(line) as Map<dynamic, dynamic>,
            );
          } on Object catch (e) {
            // Not a well-formed Syncplay frame: a broken server, or something
            // on the path probing for a downgrade. Both are refusals to
            // encrypt, and neither may reach the Hello.
            settled = true;
            if (stale()) return;
            _failTlsNegotiation('malformed STARTTLS answer: $e');
            return;
          }

          if (decoded is TlsMessage && decoded.startTls) {
            settled = true;
            if (stale()) return;
            sub.pause();
            final Socket secure;
            try {
              secure = await _secureUpgrade(plain, host: server);
            } on Object catch (e) {
              // Chain, hostname or handshake rejected. The server said it would
              // encrypt and then could not prove who it is — the one case where
              // continuing in the clear would be most dangerous.
              if (stale()) return;
              _failTlsNegotiation('TLS handshake failed: $e');
              return;
            }
            // The await above can outlive a teardown — drop the upgraded socket
            // rather than binding it over a newer attempt.
            if (stale()) {
              secure.destroy();
              return;
            }
            // Drop any half-line left over from the plaintext phase so bytes
            // chosen by whoever answered the negotiation cannot be spliced onto
            // the front of the first decrypted frame.
            _framer.reset();
            _channelSecure = true;
            _bindSocket(secure, generation);
            _sendHello();
            return;
          }

          // Anything else is the negotiation ending without encryption: an
          // explicit `startTLS: false` (upstream's "server has no TLS"), an
          // Error frame (what a pre-TLS server answers an unknown command
          // with), or a server that skips the answer and starts talking
          // protocol. Fail closed on all three.
          settled = true;
          if (stale()) return;
          _failTlsNegotiation(switch (decoded) {
            TlsMessage() => 'server declined STARTTLS',
            ErrorMessage(:final message) =>
              'server rejected STARTTLS: $message',
            _ => 'server skipped the STARTTLS answer',
          });
          return;
        }
      },
      onError: (Object e) {
        if (settled) return;
        settled = true;
        if (stale()) return;
        onLog?.call('tls negotiation error: $e');
        // Transport-level, not a refusal — treat it as a lost link so a flaky
        // network still reconnects instead of stranding an established session.
        _onConnectionLost();
      },
      onDone: () {
        if (settled) return;
        settled = true;
        if (stale()) return;
        onLog?.call('tls negotiation closed before an answer');
        _onConnectionLost();
      },
    );
  }

  /// STARTTLS ended without an encrypted channel. Terminal for the connection:
  /// MeowWatch speaks Syncplay only over TLS, so there is nothing to retry into
  /// and a backoff loop would just hide a downgrade attempt behind
  /// "reconnecting…". Destroys the plaintext socket before anything can be
  /// written to it (#264).
  void _failTlsNegotiation(String detail) {
    onLog?.call('STARTTLS refused: $detail');
    _stopReconnecting();
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    _channelSecure = false;
    emitConnectionState(
      SyncConnectionState(
        status: SyncConnectionStatus.error,
        message:
            'Could not open a secure connection to $_server:$_port '
            '($detail). MeowWatch only joins rooms over TLS.',
      ),
    );
  }

  void _bindSocket(Socket socket, int generation) {
    _socket = socket;
    // onDone/onError can fire *after* we've already torn this socket down (a
    // destroy() during reconnect still flushes a final close event). Guard on
    // the generation so only the currently-live socket can trigger a reconnect
    // — otherwise a stale callback would schedule a second one, double-counting
    // the backoff and resetting the timer.
    socket.listen(
      _onChunk,
      onError: (Object e) {
        if (generation != _generation) return;
        onLog?.call('socket error: $e');
        _onConnectionLost();
      },
      onDone: () {
        if (generation != _generation) return;
        _onConnectionLost();
      },
    );
  }

  void _onChunk(List<int> chunk) {
    // Any byte from the server proves the link is alive — reset the watchdog.
    _watchdog.bump();
    final List<String> lines;
    try {
      lines = _framer.addChunk(chunk);
    } on LineOverflowException catch (e) {
      // A peer streaming bytes without ever ending a line is broken or hostile
      // (#187) — treat the link as dead rather than buffering toward OOM. The
      // reconnect path starts over with a fresh framer.
      onLog?.call('protocol error: $e — dropping connection');
      _onConnectionLost();
      return;
    }
    for (final line in lines) {
      if (line.isEmpty) continue;
      late Map<String, Object?> decoded;
      late ServerMessage msg;
      try {
        decoded = json.decode(line) as Map<String, Object?>;
        // Raw traffic is verbose-only except server Error frames, whose detail
        // remains useful at neat. Redact the already-decoded object so verbose
        // logging does not parse every heartbeat a second time.
        final isError = decoded.containsKey('Error');
        if (_shouldFormatLog(verboseOnly: !isError)) {
          onLog?.call('<< ${redactSecretsForLog(decoded)}');
        }
        msg = decodeServerMessage(decoded, selfRoom: _room);
      } on FormatException {
        continue;
      }
      _handleMessage(msg);
    }
  }

  void _sendHello() {
    // Always request the ORIGINAL name, never the server-assigned one — see
    // [_requestedUsername]. This is what stops the "_" suffix compounding on
    // each reconnect.
    _send(
      encodeHello(
        username: _requestedUsername,
        room: _room,
        password: _password,
      ),
    );
  }

  void _handleMessage(ServerMessage msg) {
    switch (msg) {
      case HelloMessage(:final username):
        _loggedIn = true;
        _everLoggedIn = true;
        // A completed login means the (re)connect succeeded — reset the backoff
        // so the next drop starts over from the short end.
        _reconnectAttempt = 0;
        // The server appends a suffix to dedupe a name collision ("meow" ->
        // "meow_") and echoes the assigned name here. Adopt it so our own
        // identity matches what peers and the chat echo call us — otherwise
        // chat-bubble ownership and the gear member list show the wrong name
        // and flip self/peer (#40).
        if (username != null && username.isNotEmpty) _username = username;
        emitConnectionState(
          SyncConnectionState(
            status: SyncConnectionStatus.connected,
            username: _username,
          ),
        );
        // Ask for the room roster immediately — otherwise a client that joins
        // without a file loaded never learns who is already here (it would only
        // request the list when announcing a file), and sits on "waiting for a
        // friend" while everyone else can see it.
        _send(encodeList());
      case PresenceMessage(:final events, :final files):
        for (final e in events) {
          // Drop only our own events (current assigned name); a real peer that
          // happens to share an old name of ours must still surface.
          if (!_isSelf(e.username)) emitPresence(e);
        }
        for (final f in files) {
          if (!_isSelf(f.username)) emitPeerFile(f);
        }
      case PeerFileMessage(:final files):
        for (final f in files) {
          if (!_isSelf(f.username)) emitPeerFile(f);
        }
      case RosterMessage(:final usernames, :final files):
        for (final name in usernames) {
          if (!_isSelf(name)) {
            emitPresence(
              PresenceEvent(
                username: name,
                kind: PresenceKind.joined,
                fromRoster: true,
              ),
            );
          }
        }
        for (final f in files) {
          if (!_isSelf(f.username)) emitPeerFile(f);
        }
        if (!_rosterGreeted) {
          _rosterGreeted = true;
          final others = usernames.where((n) => !_isSelf(n)).toList();
          emitInitialRoster(others);
        }
      case ChatServerMessage(:final message):
        emitChat(message);
      case ErrorMessage(:final message):
        // A server protocol error is a deliberate rejection (bad room/password,
        // room full, kicked) — the server closes the socket right after. Stop
        // reconnecting so that trailing close doesn't restart an endless loop
        // with the same bad credentials; leave the user on the actionable error.
        _stopReconnecting();
        final old = _socket;
        _socket = null;
        old?.destroy();
        _loggedIn = false;
        _channelSecure = false;
        emitConnectionState(
          SyncConnectionState(
            status: SyncConnectionStatus.error,
            message: message,
          ),
        );
      case StateMessage():
        _handleState(msg);
      case TlsMessage():
      case UnknownMessage():
        break;
    }
  }

  void _handleState(StateMessage msg) {
    // Track the server/client ignore handshake.
    if (msg.serverIgnore != null) {
      _serverIgnore = msg.serverIgnore!;
      _clientIgnore = 0;
    } else if (msg.clientIgnore != null && msg.clientIgnore == _clientIgnore) {
      _clientIgnore = 0;
    }

    // Remember the latency timestamp we must echo back.
    if (msg.latencyCalculation != null) {
      _serverLatencyCalculation = msg.latencyCalculation;
    }

    // Measure our RTT: the server echoes the clientLatencyCalculation we sent
    // last, so the round trip is now - that timestamp. Without this, _ping.rtt
    // stays 0 and forwardDelay never compensates for network latency.
    final rtt = rttSampleFromEcho(
      echoedTimestamp: msg.clientLatencyCalculation,
      nowEpochSeconds: _ping.newTimestamp(),
    );
    if (rtt != null) _ping.recordRtt(rtt);

    // Decide whether the local player should follow the room's global state.
    // Skipped while mid-handshake on our own change, OR while we have a local
    // change queued but not yet sent (it would otherwise be clobbered by the
    // stale global state the server is still echoing).
    final ignoringOwnChange =
        _pendingStateChange || (_clientIgnore != 0 && _serverIgnore == 0);
    if (msg.peer != null) {
      // Advance position by the one-way delay if the room is playing.
      final global = msg.peer!.paused
          ? msg.peer!
          : PeerPlayState(
              position:
                  msg.peer!.position +
                  Duration(milliseconds: (_ping.forwardDelay * 1000).round()),
              paused: msg.peer!.paused,
              doSeek: msg.peer!.doSeek,
              setBy: msg.peer!.setBy,
            );
      // Remember even when we do not apply: markSourceOpen needs the room
      // position after a load that FOLLOW left at 0 (Check 6 / Debian SOP #6).
      if (global.setBy != null) lastObservedRoomState = global;
      if (!ignoringOwnChange) {
        // Feed the stall detector the peer's RAW state (the forward-delay offset
        // above is constant, so it would only add noise to advancement tracking).
        _peerStall.update(
          position: msg.peer!.position,
          paused: msg.peer!.paused,
          doSeek: msg.peer!.doSeek,
        );
        var action = decideFollow(
          global: global,
          localPaused: _localPaused,
          localPosition: _localPosition,
          username: _username,
          peerStalled: _peerStall.stalled,
        );
        // Official Syncplay initialises the player from the first named-setter
        // global even when that State has doSeek=false. Without this, a joiner
        // who is merely *behind* the room (the product connect-then-load path)
        // logs FOLLOW apply=false forever and never emits peerState.
        if (!action.shouldApply &&
            !_initialCatchUpDone &&
            global.setBy != null &&
            global.setBy != _username) {
          final behindBy = global.position - _localPosition;
          if (global.paused != _localPaused ||
              behindBy > SyncplayConstants.rewindThreshold) {
            action = FollowAction.apply(
              position: global.position,
              paused: global.paused,
            );
          }
        }
        if (_shouldFormatLog(verboseOnly: !action.shouldApply)) {
          onLog?.call(
            'FOLLOW global(pos=${global.positionSeconds}s paused=${global.paused} '
            'doSeek=${global.doSeek} setBy=${global.setBy}) '
            'local(pos=${_localPosition.inMilliseconds / 1000}s paused=$_localPaused) '
            'stalled=${_peerStall.stalled} => apply=${action.shouldApply}',
          );
        }
        if (action.shouldApply) {
          _initialCatchUpDone = true;
          // Surface this as a notification BEFORE we overwrite our local snapshot
          // below — the classifier compares the peer's target to where we were.
          final activity = classifySyncActivity(
            global: global,
            localPaused: _localPaused,
            localPosition: _localPosition,
          );
          if (activity != null) emitActivity(activity);

          // Adopt the applied state into our local cache immediately. The video
          // applies it asynchronously, so without this the very next heartbeat
          // would report the STALE pre-apply state (e.g. pos=0 paused=true) and
          // the server would treat that as a brand-new change — the root of the
          // ping-pong fight.
          _localPosition = action.position;
          _localPaused = action.paused;
          emitPeerState(
            PeerPlayState(
              position: action.position,
              paused: action.paused,
              doSeek: global.doSeek,
              setBy: global.setBy,
            ),
          );
        }
      }
    }

    _replyState();
  }

  /// Send our own State in response to the server's (the heartbeat).
  void _replyState() {
    final stateChange = _pendingStateChange;
    if (stateChange) {
      _clientIgnore += 1;
    }

    _send(
      encodeState(
        position: _localPosition,
        paused: _localPaused,
        doSeek: _pendingDoSeek,
        latencyCalculation: _serverLatencyCalculation,
        clientLatencyCalculation: _ping.newTimestamp(),
        clientRtt: _ping.rtt,
        clientIgnore: _clientIgnore,
        serverIgnore: _serverIgnore,
      ),
    );

    // Reset one-shot flags; serverIgnore is cleared once echoed.
    _pendingStateChange = false;
    _pendingDoSeek = false;
    _serverIgnore = 0;
  }

  void _send(Map<String, Object?> message) {
    if (!const bool.fromEnvironment('dart.vm.product') &&
        !const bool.fromEnvironment('dart.vm.profile')) {
      _debugSentMessages.add(message);
      // A long debug session sends a State heartbeat every second; unbounded
      // recording is a slow, steady leak (#199). Keep only the newest entries.
      if (_debugSentMessages.length > debugSentMessagesCap) {
        _debugSentMessages.removeRange(
          0,
          _debugSentMessages.length - debugSentMessagesCap,
        );
      }
    }
    final socket = _socket;
    if (socket == null) return;
    if (!_channelSecure) {
      // Unreachable through the normal state machine — the only socket that is
      // ever bound is the upgraded one. Kept as the backstop that makes "no
      // sensitive frame leaves before the handshake completes" a property of
      // the writer rather than of the call sites (#264).
      onLog?.call('refused to send on an unencrypted channel');
      return;
    }
    final line = json.encode(message);
    // Log a redacted copy — the Hello carries the room password, which must not
    // land in the now-persistent / exportable diagnostic log.
    if (_shouldFormatLog(verboseOnly: true)) {
      onLog?.call('>> ${redactSecretsForLog(message)}');
    }
    try {
      socket.add(utf8.encode('$line\r\n'));
    } on Object catch (e) {
      // A socket write can legitimately fail while the link is going away: a
      // deliberate leave flushes the socket, and dart:io marks the sink "bound
      // to a stream" for the duration of that flush, so an inbound State landing
      // in the same window would otherwise throw a StateError straight out of
      // the socket's data handler and abort the message pump. A half-open link
      // behaves the same way. Never silent — the watchdog owns recovery, this
      // only records that the byte never left.
      onLog?.call('send failed (link closing): $e');
    }
  }

  /// Most-recent outbound messages kept in [debugSentMessages]; older entries
  /// are dropped so debug builds don't leak over a long session.
  @visibleForTesting
  static const int debugSentMessagesCap = 200;

  final List<Map<String, Object?>> _debugSentMessages = [];

  /// Test hook: outbound messages recorded by [_send] (debug builds only).
  @visibleForTesting
  List<Map<String, Object?>> get debugSentMessages =>
      List.unmodifiable(_debugSentMessages);

  void _sendRaw(Socket socket, Map<String, Object?> message) {
    socket.add(utf8.encode('${json.encode(message)}\r\n'));
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {
    if (!_loggedIn) return;
    _send(encodeFile(name: name, sizeBytes: size, duration: duration));
    _send(encodeList());
  }

  /// Ask the server for the current roster. The watch UI calls this after it
  /// starts listening so the one-shot roster greeting is received.
  void requestList() {
    if (!_loggedIn || !_channelSecure) return;
    _send(encodeList());
  }

  @override
  void updateLocalState({required Duration position, required bool paused}) {
    _prevLocalPosition = _localPosition;
    _prevLocalPaused = _localPaused;
    _localPosition = position;
    _localPaused = paused;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {
    _pendingStateChange = true;
    if (doSeek) _pendingDoSeek = true;

    // Announce our own action locally (issue #27). The peer-side path in
    // _handleState only fires for *peers*; without this our own play/pause/seek
    // would be silent on our own screen. Suppressed until we have a username to
    // attribute it to.
    if (!_loggedIn || _username.isEmpty) return;
    final activity = classifyLocalActivity(
      doSeek: doSeek,
      paused: _localPaused,
      wasPaused: _prevLocalPaused,
      position: _localPosition,
      previousPosition: _prevLocalPosition,
      username: _username,
    );
    if (activity != null) emitActivity(activity);
  }

  /// Test hook: simulate a completed login so local-change classification has a
  /// username to attribute, without standing up a real socket/handshake. Sets
  /// the requested name to match, mirroring a real connect().
  @visibleForTesting
  void debugMarkLoggedIn(String username) {
    _requestedUsername = username;
    _username = username;
    _loggedIn = true;
    _everLoggedIn = true;
  }

  /// Test hook: stand in for the socket a completed handshake would have bound,
  /// so tests that only care about what the client *says* can skip the
  /// negotiation. Marks the channel secure for the same reason — the only
  /// socket production ever binds is the upgraded one.
  @visibleForTesting
  void debugAttachSocket(Socket socket) {
    _socket = socket;
    _channelSecure = true;
  }

  @visibleForTesting
  void debugAttachLoggedInSocket(Socket socket, {required String username}) {
    debugMarkLoggedIn(username);
    debugAttachSocket(socket);
  }

  /// Test hook: true once STARTTLS has completed and the bound socket is the
  /// encrypted one. The gate that [_send] enforces.
  @visibleForTesting
  bool get debugChannelSecure => _channelSecure;

  /// Test hook: bind a socket the way a *failed* handshake would have left
  /// things — live socket, unconfirmed channel — so the [_send] gate can be
  /// exercised directly rather than only through the negotiation.
  @visibleForTesting
  void debugAttachUnsecuredSocket(Socket socket) {
    _socket = socket;
    _channelSecure = false;
  }

  /// Test hook: seed an already-established session (requested name + the
  /// server-assigned identity equal), without dialing a socket. Lets a test
  /// exercise the reconnect Hello path.
  @visibleForTesting
  void debugSeedIdentity(String username) {
    _requestedUsername = username;
    _username = username;
  }

  /// Test hook: the name the next Hello will request. Stays the originally
  /// requested name across reconnects, even after the server assigns a suffixed
  /// one — proving the "_" suffix can't compound (#93).
  @visibleForTesting
  String get debugRequestedUsername => _requestedUsername;

  /// Test hook: run [_sendHello] without a socket so the requested username is
  /// recorded in [debugSentMessages].
  @visibleForTesting
  void debugSendHello() => _sendHello();

  /// Test hook: pretend the server fell silent / the socket dropped, exercising
  /// the reconnect state machine without a real network. Mirrors what the
  /// watchdog, socket onDone, and socket onError all funnel into.
  @visibleForTesting
  void debugSimulateConnectionLost() => _onConnectionLost();

  /// Test hook: how many reconnect attempts have been scheduled since the last
  /// successful login (resets to 0 on Hello). Lets a test assert the backoff
  /// advances on repeated drops.
  @visibleForTesting
  int get debugReconnectAttempt => _reconnectAttempt;

  /// Test hook: is a reconnect currently armed?
  @visibleForTesting
  bool get debugReconnectScheduled => _reconnectTimer?.isActive ?? false;

  /// Test hook: route a decoded server message through the normal handler,
  /// without a socket — e.g. to exercise the fatal-error stop path.
  @visibleForTesting
  void debugHandleMessage(ServerMessage msg) => _handleMessage(msg);

  /// Test hook: feed raw socket bytes through the live-chunk path, e.g. to
  /// exercise the line-overflow guard (#187) without a real socket.
  @visibleForTesting
  void debugReceiveChunk(List<int> chunk) => _onChunk(chunk);

  @override
  void sendChat(String text) {
    if (_loggedIn) _send(encodeChat(text));
  }

  /// Announce a deliberate departure so peers can distinguish a clean leave from
  /// a connection drop (issue #92). Shared by the Leave button ([disconnect]) and
  /// app close ([disposeBackend]); call only when [_loggedIn].
  ///
  /// Best-effort: give the bye a very short chance to leave before destroying
  /// the socket. The timeout stays bounded because a half-open socket flush can
  /// otherwise wedge teardown.
  Future<void> _announceLeaving() async {
    _send(encodeChat(encodeLeaving()));
    final socket = _socket;
    if (socket == null) return;
    try {
      await socket.flush().timeout(const Duration(milliseconds: 120));
    } on Object {
      // Leaving is advisory; teardown must continue even if the packet cannot
      // be flushed to a half-open connection.
    }
  }

  @override
  Future<void> disconnect() async {
    // Cancel the watchdog and any pending reconnect FIRST so a timer can't fire
    // during teardown and resurrect the link.
    _stopReconnecting();
    if (_loggedIn) await _announceLeaving();
    // destroy(), not close(): a half-open socket's close() awaits a flush that
    // can never complete (the peer is gone), which is exactly what wedged the
    // "Leave room" button. destroy() drops it immediately. Clear _socket first
    // so the trailing close event can't see itself as live.
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    _channelSecure = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  /// Window-close fast path: send the advisory leave packet if possible, give
  /// it one bounded flush, then tear down so app shutdown can continue to
  /// `exit(0)`.
  ///
  /// The OS close path still cannot depend on an unbounded socket Future,
  /// because a wedged native/network flush can leave the visible window gone
  /// while Dart timers keep running headless (#148). The caller runs this behind
  /// [runAppCloseHook]'s timeout and the window close handler's hard-exit
  /// watchdog.
  Future<void> disconnectForAppClose({
    Duration flushTimeout = const Duration(milliseconds: 300),
  }) async {
    _stopReconnecting();
    final old = _socket;
    if (_loggedIn) {
      _send(encodeChat(encodeLeaving()));
      if (old != null) {
        try {
          await old.flush().timeout(flushTimeout);
        } catch (_) {}
      }
    }
    _loggedIn = false;
    _channelSecure = false;
    _socket = null;
    // Keep the close hook bounded and tiny. Destroying the socket or emitting
    // UI-facing disconnect state belongs to normal Leave/dispose; app close is
    // about to `exit(0)`, and doing native/network teardown inline has already
    // left hidden headless processes behind on Windows (#148).
    if (old != null) Timer.run(old.destroy);
  }

  @override
  Future<void> disposeBackend() async {
    // App is closing — also a deliberate leave, so announce it. No-op if a prior
    // disconnect() already cleared _loggedIn.
    _stopReconnecting();
    if (_loggedIn) await _announceLeaving();
    _loggedIn = false;
    _channelSecure = false;
    final old = _socket;
    _socket = null;
    old?.destroy();
  }
}
