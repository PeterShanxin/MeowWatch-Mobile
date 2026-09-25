import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// State-machine coverage for the half-open-connection fix. A real handshake
/// needs a TLS server with a cert the client trusts (it rejects bad certs), so
/// the socket plumbing is exercised manually in the app; here we drive the
/// reconnect logic through test hooks that mirror exactly what the watchdog,
/// socket onDone, and socket onError funnel into.
void main() {
  late SyncplayClient client;
  late List<SyncConnectionStatus> statuses;

  setUp(() {
    client = SyncplayClient();
    statuses = <SyncConnectionStatus>[];
    client.connectionState.listen((s) => statuses.add(s.status));
  });

  tearDown(() => client.dispose());

  test('a lost link moves to reconnecting and arms a retry', () async {
    client.debugMarkLoggedIn('me');
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);

    expect(statuses, contains(SyncConnectionStatus.reconnecting));
    expect(client.debugReconnectScheduled, isTrue);
    expect(client.debugReconnectAttempt, 1);
  });

  test('a scheduled reconnect logs its attempt number and delay', () async {
    final lines = <String>[];
    final logged = SyncplayClient(onLog: lines.add);
    addTearDown(logged.dispose);

    logged.debugMarkLoggedIn('me');
    logged.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);

    expect(
      lines,
      contains(
        predicate<String>(
          (l) => l.startsWith('reconnect: attempt 1 in ') && l.endsWith('ms'),
        ),
      ),
      reason:
          'the gap between "connection lost" and the next Hello must be '
          'visible in the log (#156)',
    );
  });

  test('repeated drops advance the backoff attempt counter', () async {
    client.debugMarkLoggedIn('me');
    client.debugSimulateConnectionLost();
    client.debugSimulateConnectionLost();
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);

    expect(client.debugReconnectAttempt, 3);
    expect(client.debugReconnectScheduled, isTrue);
  });

  test('manual disconnect cancels reconnect and stays disconnected', () async {
    client.debugMarkLoggedIn('me');
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(client.debugReconnectScheduled, isTrue);

    await client.disconnect();
    expect(
      client.debugReconnectScheduled,
      isFalse,
      reason: 'leaving must cancel the armed retry',
    );
    expect(statuses.last, SyncConnectionStatus.disconnected);

    // A drop arriving after a manual leave must NOT restart reconnection.
    final before = List<SyncConnectionStatus>.from(statuses);
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(statuses, before, reason: 'no new status after manual leave');
    expect(client.debugReconnectScheduled, isFalse);
  });

  test(
    'disconnect with no live socket completes quickly (never hangs)',
    () async {
      // The wedged "Leave room" came from awaiting close() on a half-open socket.
      // disconnect() must always resolve promptly regardless of socket state.
      await client.disconnect().timeout(const Duration(seconds: 1));
      expect(statuses.last, SyncConnectionStatus.disconnected);
    },
  );

  test('disconnect with a live socket bounds the leaving flush', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = <Socket>[];
    server.listen((s) {
      accepted.add(s);
      s.listen((_) {}); // keep the connection open and otherwise silent.
    });
    final socket = await Socket.connect('127.0.0.1', server.port);
    addTearDown(() async {
      socket.destroy();
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    client.debugAttachLoggedInSocket(socket, username: 'me');

    await client.disconnect().timeout(const Duration(milliseconds: 500));
    await Future<void>.delayed(Duration.zero);
    expect(statuses.last, SyncConnectionStatus.disconnected);
  });

  test('a fatal server error stops reconnecting (no endless loop)', () async {
    // A rejected room/password: the server sends Error then closes the socket.
    // The trailing close must NOT restart the loop with the same bad creds —
    // the user stays on the actionable error. (Codex review #49.)
    client.debugHandleMessage(const ErrorMessage('Invalid password'));
    await Future<void>.delayed(Duration.zero);

    expect(statuses.last, SyncConnectionStatus.error);
    expect(client.debugReconnectScheduled, isFalse);

    // The socket's onDone arrives after Error — simulate it; still no reconnect.
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(statuses, isNot(contains(SyncConnectionStatus.reconnecting)));
    expect(statuses.last, SyncConnectionStatus.error);
  });

  test(
    'initial silent endpoint fails instead of reconnecting forever',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final accepted = <Socket>[];
      server.listen((s) {
        accepted.add(s);
        s.listen((_) {}); // read & ignore; never answer TLS/Hello
      });
      addTearDown(() async {
        for (final s in accepted) {
          s.destroy();
        }
        await server.close();
      });

      final silent = SyncplayClient(
        livenessTimeout: const Duration(milliseconds: 30),
      );
      final states = <SyncConnectionState>[];
      silent.connectionState.listen(states.add);
      addTearDown(silent.dispose);

      await silent.connect(
        server: '127.0.0.1',
        port: server.port,
        username: 'me',
        room: 'r',
      );
      await _until(
        () => states.any((s) => s.status == SyncConnectionStatus.error),
      );

      expect(states.last.status, SyncConnectionStatus.error);
      expect(states.last.message, contains('stayed silent'));
      expect(states.last.message, contains('127.0.0.1:${server.port}'));
      expect(silent.debugReconnectScheduled, isFalse);
    },
  );

  test('manual leave mid-handshake tears down and never reconnects', () async {
    // A server that accepts the TCP connection but never answers the TLS
    // request leaves the client stuck in negotiation with the (unbound)
    // handshake socket live. Leaving now must destroy it and stay disconnected
    // — the generation guard must stop the dangling negotiation from later
    // binding a zombie socket. (Codex review #49.)
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = <Socket>[];
    server.listen((s) {
      accepted.add(s);
      s.listen((_) {}); // read & ignore; never reply
    });
    addTearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    await client.connect(
      server: '127.0.0.1',
      port: server.port,
      username: 'me',
      room: 'r',
    );
    // We're now mid-handshake (handshaking emitted, no Hello will ever arrive).
    await _until(() => statuses.contains(SyncConnectionStatus.handshaking));
    expect(statuses, contains(SyncConnectionStatus.handshaking));

    await client.disconnect().timeout(const Duration(seconds: 1));
    expect(statuses.last, SyncConnectionStatus.disconnected);
    expect(client.debugReconnectScheduled, isFalse);

    // Let any late negotiation callback fire — it must be ignored.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(statuses, isNot(contains(SyncConnectionStatus.reconnecting)));
    expect(statuses.last, SyncConnectionStatus.disconnected);
  });

  test('a reconnect returns to the endpoint the session started on', () async {
    // Endpoint discovery belongs to the lobby and never to a live session:
    // moving a running room to another candidate would silently leave the peer
    // behind on the old one (#234).
    final home = await ServerSocket.bind('127.0.0.1', 0);
    final elsewhere = await ServerSocket.bind('127.0.0.1', 0);
    var homeDials = 0;
    var elsewhereDials = 0;
    home.listen((s) {
      homeDials++;
      s.listen((_) {}, onError: (Object _) {});
    });
    elsewhere.listen((s) {
      elsewhereDials++;
      s.listen((_) {}, onError: (Object _) {});
    });
    addTearDown(() async {
      await home.close();
      await elsewhere.close();
    });

    await client.connect(
      server: '127.0.0.1',
      port: home.port,
      username: 'me',
      room: 'r',
    );
    await _until(() => homeDials == 1);

    client.debugMarkLoggedIn('me');
    client.debugSimulateConnectionLost();
    await _until(() => homeDials == 2);

    expect(homeDials, 2, reason: 'the same endpoint, dialled again');
    expect(
      elsewhereDials,
      0,
      reason: 'a live session never fails over to another candidate',
    );
  });
}

/// Poll [predicate] until true or a hard deadline, so tests don't hang forever.
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
