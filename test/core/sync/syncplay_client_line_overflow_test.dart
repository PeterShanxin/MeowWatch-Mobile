import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// #187: a server (or MITM before TLS) streaming bytes without ever sending a
/// newline must not grow the framer buffer unboundedly (OOM). The client
/// treats the overflow as a dead link: reconnect after login, actionable error
/// before it.
void main() {
  test('a no-newline byte flood after login drops the link and '
      'reconnects', () async {
    final lines = <String>[];
    final client = SyncplayClient(onLog: lines.add);
    addTearDown(client.dispose);
    client.debugMarkLoggedIn('me');

    final flood = List<int>.filled(LineFramer.defaultMaxLineBytes + 1, 0x41);
    client.debugReceiveChunk(flood);
    await Future<void>.delayed(Duration.zero);

    expect(client.debugReconnectScheduled, isTrue);
    expect(client.debugReconnectAttempt, 1);
    expect(
      lines,
      contains(predicate<String>((l) => l.contains('overflow'))),
      reason: 'the drop must be attributable in the diagnostic log',
    );
  });

  test('a pre-TLS flood without a newline fails the initial connect', () async {
    // The negotiation listener is a separate addChunk call site; a flood there
    // (before any login) is a malformed STARTTLS answer, not an unreachable
    // host, and must not buffer forever or loop reconnects.
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = <Socket>[];
    server.listen((s) {
      accepted.add(s);
      s.listen((_) {}); // swallow the client's TLS request
      s.add(List<int>.filled(LineFramer.defaultMaxLineBytes * 2, 0x41));
    });
    addTearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    final states = <SyncConnectionState>[];
    final client = SyncplayClient();
    client.connectionState.listen(states.add);
    addTearDown(client.dispose);

    await client.connect(
      server: '127.0.0.1',
      port: server.port,
      username: 'me',
      room: 'r',
    );
    await _until(
      () => states.any((s) => s.status == SyncConnectionStatus.error),
    );

    expect(states.last.status, SyncConnectionStatus.error);
    expect(states.last.message, contains('malformed STARTTLS answer'));
    expect(states.last.message, contains('secure connection'));
    expect(client.debugReconnectScheduled, isFalse);
  });
}

/// Poll [predicate] until true or a hard deadline, so tests don't hang forever.
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
