import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// disconnect() must broadcast a leaving signal before tearing down when
/// the client is logged in, so peers can distinguish a clean leave from a
/// connection drop (issue #92).
void main() {
  late SyncplayClient client;

  setUp(() {
    client = SyncplayClient();
  });

  tearDown(() => client.dispose());

  test('disconnect sends leaving signal when logged in', () async {
    client.debugMarkLoggedIn('me');

    await client.disconnect();

    // The leaving control message should appear in captured outbound sends.
    expect(
      client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
      isTrue,
      reason: 'disconnect() must send a leaving signal before closing',
    );
  });

  test('disconnect sends nothing when not logged in', () async {
    // Deliberately not calling debugMarkLoggedIn — client is not logged in.
    await client.disconnect();

    expect(client.debugSentMessages, isEmpty);
  });

  test('app-close disconnect sends leaving signal synchronously', () async {
    client.debugMarkLoggedIn('me');

    final close = client.disconnectForAppClose();

    expect(
      client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
      isTrue,
      reason: 'window close must announce leaving without awaiting a socket',
    );
    await close;
  });

  test(
    'app-close disconnect gives the leaving packet a bounded flush',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final receivedLines = <String>[];
      final firstLine = Completer<String>();
      final accepted = <Socket>[];

      server.listen((socket) {
        accepted.add(socket);
        utf8.decoder.bind(socket).transform(const LineSplitter()).listen((
          line,
        ) {
          receivedLines.add(line);
          if (!firstLine.isCompleted) firstLine.complete(line);
        });
      });

      addTearDown(() async {
        for (final socket in accepted) {
          socket.destroy();
        }
        await server.close();
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      client.debugAttachSocket(socket);
      client.debugMarkLoggedIn('me');

      await client.disconnectForAppClose().timeout(
        const Duration(milliseconds: 500),
      );

      final line = await firstLine.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => receivedLines.join('\n'),
      );

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['Chat'], encodeLeaving());
    },
  );

  test(
    'app close (dispose) also sends a leaving signal when logged in',
    () async {
      client.debugMarkLoggedIn('me');

      await client.dispose();

      expect(
        client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
        isTrue,
        reason: 'closing the app should announce a deliberate departure',
      );
    },
  );

  test('leave then dispose does not double-send the leaving signal', () async {
    client.debugMarkLoggedIn('me');

    await client.disconnect();
    await client.dispose();

    final leavingCount = client.debugSentMessages
        .where((m) => m['Chat'] == encodeLeaving())
        .length;
    expect(leavingCount, 1);
  });
}
