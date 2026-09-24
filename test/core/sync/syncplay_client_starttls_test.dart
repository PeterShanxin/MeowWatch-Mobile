import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

/// #264 — STARTTLS is mandatory and fails closed.
///
/// MeowWatch has no plaintext mode. The Hello that follows the upgrade carries
/// the username, the room name and the room password; `Set`, `Chat` and `State`
/// after it carry the file name, the chat and the watch position. So every way
/// a server (or something on the path) can decline to encrypt has to end the
/// connection with an error instead of continuing in the clear.
///
/// Each test drives the real client against a real loopback server and asserts
/// on the bytes that actually left the socket unencrypted — not on internal
/// state — so a future refactor that reintroduces a downgrade fails here.
void main() {
  group('STARTTLS refusals fail closed', () {
    test('an Error answer does not downgrade to plaintext', () async {
      final probe = await _connectAgainst(
        answer: json.encode({
          'Error': {'message': 'unknown command startTLS'},
        }),
      );

      probe.expectOnlyTheTlsRequest();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('secure connection'));
      expect(probe.terminalMessage, contains('rejected STARTTLS'));
      expect(
        probe.reconnectArmed,
        isFalse,
        reason: 'a refusal is deterministic; retrying only hides it',
      );
      expect(probe.channelSecure, isFalse);
    });

    test('an explicit startTLS:false answer is refused, not accepted '
        'in the clear', () async {
      // What upstream syncplay-server replies when it has no TLS configured.
      final probe = await _connectAgainst(
        answer: json.encode({
          'TLS': {'startTLS': 'false'},
        }),
      );

      probe.expectOnlyTheTlsRequest();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('declined STARTTLS'));
      expect(probe.channelSecure, isFalse);
    });

    test(
      'a stripped negotiation (no answer at all) fails the connect',
      () async {
        final probe = await _connectAgainst(answer: null);

        probe.expectOnlyTheTlsRequest();
        expect(probe.terminalStatus, SyncConnectionStatus.error);
        expect(probe.terminalMessage, contains('stayed silent'));
        expect(probe.channelSecure, isFalse);
      },
    );

    test('a malformed answer is refused rather than parsed past', () async {
      final probe = await _connectAgainst(rawAnswer: 'not json at all\r\n');

      probe.expectNothingSensitiveOnTheWire();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('malformed STARTTLS answer'));
      expect(probe.channelSecure, isFalse);
    });

    test('a well-formed frame with the wrong shape is refused', () async {
      final probe = await _connectAgainst(rawAnswer: '{"TLS": 5}\r\n');

      probe.expectNothingSensitiveOnTheWire();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('malformed STARTTLS answer'));
    });

    test('an oversized STARTTLS answer with no newline is malformed', () async {
      final probe = await _connectAgainst(
        rawBytes: Uint8List.fromList(
          List<int>.filled(LineFramer.defaultMaxLineBytes + 1, 0x41),
        ),
      );

      probe.expectNothingSensitiveOnTheWire();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('malformed STARTTLS answer'));
      expect(probe.channelSecure, isFalse);
    });

    test('invalid UTF-8 in the STARTTLS answer is refused', () async {
      final probe = await _connectAgainst(
        rawBytes: Uint8List.fromList(const [0xC3, 0x28, 0x0D, 0x0A]),
      );

      probe.expectNothingSensitiveOnTheWire();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('malformed STARTTLS answer'));
      expect(probe.channelSecure, isFalse);
    });

    test('a server that skips the answer and starts talking protocol '
        'is refused', () async {
      // The shape of an active strip: swallow the client's TLS request and
      // pretend the session is already up.
      final probe = await _connectAgainst(
        answer: json.encode({
          'Hello': {'username': 'me'},
        }),
      );

      probe.expectOnlyTheTlsRequest();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('skipped the STARTTLS answer'));
      expect(
        probe.channelSecure,
        isFalse,
        reason: 'a Hello frame must not be able to log the client in',
      );
    });

    test('connectUntilJoin returns a Hello-then-Error', () async {
      final harness = await _tlsJoinHarness();
      addTearDown(harness.dispose);

      final joining = harness.client.connectUntilJoin(
        server: '127.0.0.1',
        port: harness.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
      );
      await _until(() => harness.client.debugChannelSecure);
      harness.client.debugHandleMessage(const HelloMessage(username: 'me'));
      harness.client.debugHandleMessage(const ErrorMessage('room is full'));

      expect(await joining, contains('room is full'));
      expect(
        harness.client.lastConnectionState?.status,
        SyncConnectionStatus.error,
      );
    });

    test('connectUntilJoin keeps listening through the handoff', () async {
      final harness = await _tlsJoinHarness();
      addTearDown(harness.dispose);

      final joining = harness.client.connectUntilJoin(
        server: '127.0.0.1',
        port: harness.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
        onHandoff: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          harness.client.debugHandleMessage(const ErrorMessage('room is full'));
        },
      );
      await _until(() => harness.client.debugChannelSecure);
      harness.client.debugHandleMessage(const HelloMessage(username: 'me'));

      expect(await joining, contains('room is full'));
    });

    test('connectUntilJoin returns the named refusal', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final accepted = <Socket>[];
      server.listen((s) {
        accepted.add(s);
        s.listen((bytes) {
          if (utf8.decode(bytes, allowMalformed: true).contains('startTLS')) {
            s.add(
              utf8.encode(
                '${json.encode({
                  'Error': {'message': 'unknown command startTLS'},
                })}\r\n',
              ),
            );
          }
        }, onError: (_) {});
      });
      addTearDown(() async {
        for (final s in accepted) {
          s.destroy();
        }
        await server.close();
      });

      final client = SyncplayClient();
      addTearDown(client.dispose);
      final error = await client.connectUntilJoin(
        server: '127.0.0.1',
        port: server.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
      );

      expect(error, contains('rejected STARTTLS'));
      expect(client.debugChannelSecure, isFalse);
    });

    test('a failed TLS handshake after an accepted STARTTLS is refused', () async {
      // The server says it will encrypt, then cannot prove who it is. This runs
      // through the real SecureSocket.secure — the bytes are not a ServerHello,
      // so dart:io raises a HandshakeException exactly as a rejected
      // certificate would. Garbage is sent only after the client's TLS
      // ClientHello, so LineFramer cannot swallow it in the plaintext chunk.
      final probe = await _connectAgainst(
        answer: json.encode({
          'TLS': {'startTLS': 'true'},
        }),
        thenSendGarbage: true,
      );

      probe.expectNothingSensitiveOnTheWire();
      expect(probe.terminalStatus, SyncConnectionStatus.error);
      expect(probe.terminalMessage, contains('TLS handshake failed'));
      expect(probe.channelSecure, isFalse);
    });

    test('a real untrusted TLS certificate fails closed', () async {
      final harness = await _tlsJoinHarness(trustCertificate: false);
      addTearDown(harness.dispose);
      await harness.client.connect(
        server: '127.0.0.1',
        port: harness.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
      );
      await _until(
        () =>
            harness.client.lastConnectionState?.status ==
            SyncConnectionStatus.error,
      );
      expect(harness.client.debugChannelSecure, isFalse);
      expect(harness.secureLines, isEmpty);
      expect(
        utf8.decode(harness.plainBytes, allowMalformed: true),
        isNot(contains('hunter2')),
      );
      expect(
        harness.client.lastConnectionState?.message,
        contains('TLS handshake failed'),
      );
    });
  });

  group('successful STARTTLS', () {
    for (final leaveMode in ['disconnect', 'disposeBackend', 'appClose']) {
      test('real TLS delivers queued chat and leaving on $leaveMode', () async {
        final harness = await _tlsJoinHarness();
        addTearDown(harness.dispose);
        final client = harness.client;
        await client.connect(
          server: '127.0.0.1',
          port: harness.port,
          username: 'me',
          room: 'secret-room',
          password: 'hunter2',
        );
        await harness.helloSeen.future.timeout(const Duration(seconds: 8));
        client.debugHandleMessage(const HelloMessage(username: 'me'));
        client.sendChat('queued-before-leave-${'x' * 65536}');

        switch (leaveMode) {
          case 'disconnect':
            await client.disconnect();
            break;
          case 'disposeBackend':
            await client.disposeBackend();
            break;
          case 'appClose':
            await client.disconnectForAppClose();
            break;
        }

        await harness.leavingSeen.future.timeout(const Duration(seconds: 2));
        final chats = harness.secureLines
            .join()
            .split('\r\n')
            .where((line) => line.isNotEmpty)
            .map((line) => json.decode(line) as Map<String, dynamic>)
            .where((frame) => frame.containsKey('Chat'))
            .map((frame) => frame['Chat'] as String)
            .toList();
        expect(chats.first, startsWith('queued-before-leave-'));
        expect(chats.last, encodeLeaving());
      });
    }

    test('late TLS completion after leave cannot send Hello', () async {
      final releaseUpgrade = Completer<void>();
      final upgradeReady = Completer<void>();
      final harness = await _tlsJoinHarness(
        releaseUpgrade: releaseUpgrade,
        upgradeReady: upgradeReady,
      );
      addTearDown(() async {
        if (!releaseUpgrade.isCompleted) releaseUpgrade.complete();
        await harness.dispose();
      });

      await harness.client.connect(
        server: '127.0.0.1',
        port: harness.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
      );
      await upgradeReady.future.timeout(const Duration(seconds: 8));
      expect(harness.client.debugChannelSecure, isFalse);
      await harness.client.disconnect();
      releaseUpgrade.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(harness.secureLines, isEmpty);
      expect(harness.client.debugChannelSecure, isFalse);
      expect(
        harness.client.lastConnectionState?.status,
        SyncConnectionStatus.disconnected,
      );
    });

    test(
      'superseded TLS completion cannot write into the new session',
      () async {
        final releaseUpgrade = Completer<void>();
        final upgradeReady = Completer<void>();
        final harness = await _tlsJoinHarness(
          releaseUpgrade: releaseUpgrade,
          upgradeReady: upgradeReady,
        );
        addTearDown(() async {
          if (!releaseUpgrade.isCompleted) releaseUpgrade.complete();
          await harness.dispose();
        });

        Future<void> connect() => harness.client.connect(
          server: '127.0.0.1',
          port: harness.port,
          username: 'me',
          room: 'secret-room',
          password: 'hunter2',
        );

        await connect();
        await upgradeReady.future.timeout(const Duration(seconds: 8));
        await connect();
        await harness.helloSeen.future.timeout(const Duration(seconds: 8));
        releaseUpgrade.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(harness.connectionSecureLines, hasLength(2));
        expect(harness.connectionSecureLines.first, isEmpty);
        expect(harness.connectionSecureLines.last.join(), contains('Hello'));
      },
    );

    test('binds the upgraded socket and sends the Hello only over it', () async {
      final harness = await _tlsJoinHarness();
      addTearDown(harness.dispose);
      final client = harness.client;

      await client.connect(
        server: '127.0.0.1',
        port: harness.port,
        username: 'me',
        room: 'secret-room',
        password: 'hunter2',
      );
      await harness.helloSeen.future.timeout(const Duration(seconds: 8));

      expect(client.debugChannelSecure, isTrue);
      final hello = harness.secureLines.join();
      expect(hello, contains('Hello'));
      expect(hello, contains('secret-room'));
      expect(
        hello,
        contains('hunter2'),
        reason: 'the password rides the upgraded socket, and only that one',
      );
      expect(
        utf8.decode(harness.plainBytes, allowMalformed: true),
        isNot(contains('hunter2')),
        reason: 'nothing sensitive may precede the handshake',
      );
      // The negotiation itself is the only thing the plaintext socket ever saw.
      expect(
        utf8.decode(harness.plainBytes, allowMalformed: true).trim(),
        json.encode(encodeTlsRequest()),
      );
    });

    test('a completed handshake lets the normal message pump run', () async {
      // Guards against the fail-closed gate being over-broad: once the channel
      // is secure the client must still answer the server normally.
      final client = SyncplayClient();
      addTearDown(client.dispose);
      final sink = _NullSocket();
      client.debugAttachLoggedInSocket(sink, username: 'me');

      expect(client.debugChannelSecure, isTrue);
      client.sendChat('hello there');
      expect(
        client.debugSentMessages.map(json.encode).join(),
        contains('hello there'),
      );
      expect(sink.written.join(), contains('hello there'));
    });
  });

  group('the send gate', () {
    test(
      'refuses to write anything while the channel is not confirmed secure',
      () async {
        // The structural backstop: even with a live socket and a logged-in
        // session, an unconfirmed channel writes nothing.
        final client = SyncplayClient();
        addTearDown(client.dispose);
        final sink = _NullSocket();
        client.debugMarkLoggedIn('me');
        client.debugAttachUnsecuredSocket(sink);
        expect(client.debugChannelSecure, isFalse);

        client.sendChat('hello there');
        client.announceFile(
          name: 'movie.mkv',
          size: 1,
          duration: const Duration(seconds: 1),
        );
        client.debugSendHello();

        expect(
          sink.written,
          isEmpty,
          reason: 'no frame may reach an unencrypted socket',
        );
      },
    );
  });
}

/// Loopback server with a real TLS handshake and an exact test certificate pin.
Future<_TlsJoinHarness> _tlsJoinHarness({
  bool trustCertificate = true,
  Completer<void>? releaseUpgrade,
  Completer<void>? upgradeReady,
}) async {
  final identity = await TlsIdentity.generate();
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final accepted = <Socket>[];
  final plainBytes = <int>[];
  final secureLines = <String>[];
  final connectionSecureLines = <List<String>>[];
  final helloSeen = Completer<void>();
  final leavingSeen = Completer<void>();
  var heldUpgrade = false;
  server.listen((s) {
    accepted.add(s);
    final linesForConnection = <String>[];
    connectionSecureLines.add(linesForConnection);
    var upgrading = false;
    s.listen((bytes) {
      if (upgrading) return;
      plainBytes.addAll(bytes);
      if (!utf8.decode(plainBytes, allowMalformed: true).contains('startTLS')) {
        return;
      }
      upgrading = true;
      unawaited(
        () async {
          s.add(utf8.encode('{"TLS":{"startTLS":"true"}}\r\n'));
          await s.flush();
          final secure = await SecureSocket.secureServer(
            s,
            identity.createServerContext(),
          );
          accepted.add(secure);
          secure.done.ignore();
          secure.listen((chunk) {
            final line = utf8.decode(chunk);
            secureLines.add(line);
            linesForConnection.add(line);
            if (secureLines.join().contains('Hello') &&
                !helloSeen.isCompleted) {
              helloSeen.complete();
            }
            if (!leavingSeen.isCompleted) {
              final received = secureLines.join();
              for (final frame in received.split('\r\n')) {
                if (!frame.contains('"Chat"')) continue;
                try {
                  if ((json.decode(frame) as Map<String, dynamic>)['Chat'] ==
                      encodeLeaving()) {
                    leavingSeen.complete();
                    break;
                  }
                } on FormatException {
                  // Last frame may still be arriving in another TLS read.
                }
              }
            }
          }, onError: (Object _) {});
        }().catchError((Object _) {}),
      );
    }, onError: (_) {});
  });
  final client = SyncplayClient(
    livenessTimeout: const Duration(seconds: 3),
    secureUpgrade: (plain, subscription, {required host}) async {
      final secure = await RawSecureSocket.secure(
        plain,
        subscription: subscription,
        host: host,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (cert) =>
            trustCertificate &&
            constantTimeEqual(
              sha256.convert(cert.der).bytes,
              identity.certificateSha256,
            ),
      );
      if (releaseUpgrade != null && !heldUpgrade) {
        heldUpgrade = true;
        upgradeReady?.complete();
        await releaseUpgrade.future;
      }
      return secure;
    },
  );
  return _TlsJoinHarness(
    client: client,
    server: server,
    accepted: accepted,
    plainBytes: plainBytes,
    secureLines: secureLines,
    connectionSecureLines: connectionSecureLines,
    helloSeen: helloSeen,
    leavingSeen: leavingSeen,
  );
}

class _TlsJoinHarness {
  _TlsJoinHarness({
    required this.client,
    required this.server,
    required this.accepted,
    required this.plainBytes,
    required this.secureLines,
    required this.connectionSecureLines,
    required this.helloSeen,
    required this.leavingSeen,
  });

  final SyncplayClient client;
  final ServerSocket server;
  final List<Socket> accepted;
  final List<int> plainBytes;
  final List<String> secureLines;
  final List<List<String>> connectionSecureLines;
  final Completer<void> helloSeen;
  final Completer<void> leavingSeen;

  int get port => server.port;

  Future<void> dispose() async {
    await client.dispose();
    for (final s in accepted) {
      s.destroy();
    }
    await server.close();
  }
}

/// Drives a real [SyncplayClient] against a loopback server that answers the
/// STARTTLS request however the test asks, and records every plaintext byte the
/// client sent.
Future<_Probe> _connectAgainst({
  String? answer,
  String? rawAnswer,
  List<int>? rawBytes,
  bool thenSendGarbage = false,
}) async {
  final wire = <int>[];
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final accepted = <Socket>[];
  server.listen((s) {
    accepted.add(s);
    var sentTlsAccept = false;
    var sentGarbage = false;
    s.listen((bytes) {
      wire.addAll(bytes);
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!sentTlsAccept && text.contains('startTLS')) {
        if (rawBytes != null) s.add(rawBytes);
        if (rawAnswer != null) s.add(utf8.encode(rawAnswer));
        if (answer != null) s.add(utf8.encode('$answer\r\n'));
        sentTlsAccept = true;
        return;
      }
      // Handshake garbage must wait until the client starts TLS. Sending it
      // in the same plaintext chunk as the STARTTLS accept lets LineFramer
      // swallow it before SecureSocket.secure runs.
      if (thenSendGarbage && sentTlsAccept && !sentGarbage) {
        sentGarbage = true;
        s.add(List<int>.filled(64, 0x41));
      }
    }, onError: (_) {});
  });

  final states = <SyncConnectionState>[];
  final logs = <String>[];
  final client = SyncplayClient(
    onLog: logs.add,
    // Short so the strip/silence case does not sit on the production 12s.
    livenessTimeout: const Duration(seconds: 3),
  );
  client.connectionState.listen(states.add);

  await client.connect(
    server: '127.0.0.1',
    port: server.port,
    username: 'me',
    room: 'secret-room',
    password: 'hunter2',
  );
  await _until(() => states.any((s) => s.status == SyncConnectionStatus.error));

  final probe = _Probe(
    wire: utf8.decode(wire, allowMalformed: true),
    states: List.of(states),
    logs: List.of(logs),
    reconnectArmed: client.debugReconnectScheduled,
    channelSecure: client.debugChannelSecure,
  );

  await client.dispose();
  for (final s in accepted) {
    s.destroy();
  }
  await server.close();
  return probe;
}

class _Probe {
  _Probe({
    required this.wire,
    required this.states,
    required this.logs,
    required this.reconnectArmed,
    required this.channelSecure,
  });

  /// Everything the client sent unencrypted, as the server saw it.
  final String wire;
  final List<SyncConnectionState> states;
  final List<String> logs;
  final bool reconnectArmed;
  final bool channelSecure;

  SyncConnectionStatus? get terminalStatus =>
      states.isEmpty ? null : states.last.status;
  String get terminalMessage =>
      states.isEmpty ? '' : (states.last.message ?? '');

  /// The core invariant: no session or auth state may cross the plaintext
  /// socket, whatever the server answered.
  void expectNothingSensitiveOnTheWire() {
    expect(wire, isNot(contains('hunter2')), reason: 'room password leaked');
    expect(wire, isNot(contains('secret-room')), reason: 'room name leaked');
    expect(wire, isNot(contains('Hello')), reason: 'Hello sent in the clear');
  }

  /// Stricter form for the cases where no handshake was ever attempted: the
  /// STARTTLS request is then the only thing the socket saw.
  void expectOnlyTheTlsRequest() {
    expectNothingSensitiveOnTheWire();
    expect(wire.trim(), json.encode(encodeTlsRequest()));
  }
}

/// A [Socket] stand-in that records what was written and swallows the rest.
/// Only the sink half is exercised — the client never reads from it in these
/// tests.
class _NullSocket implements Socket {
  final List<String> written = [];

  @override
  void add(List<int> data) => written.add(utf8.decode(data));

  @override
  void destroy() {}

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Poll [predicate] until true or a hard deadline, so tests don't hang forever.
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
