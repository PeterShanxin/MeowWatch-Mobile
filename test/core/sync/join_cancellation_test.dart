import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

void main() {
  for (final dispose in [false, true]) {
    test(
      'pending secure join settles after ${dispose ? 'dispose' : 'leave'}',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = Completer<Socket>();
        server.listen(accepted.complete);
        final client = SyncplayClient();
        Socket? peer;
        addTearDown(() async {
          peer?.destroy();
          await client.dispose();
          await server.close();
        });
        final join = client.connectUntilJoin(
          server: '127.0.0.1',
          port: server.port,
          username: 'alice',
          room: 'cancel',
        );
        peer = await accepted.future;
        final startTls = Completer<void>();
        peer.listen((_) {
          if (!startTls.isCompleted) startTls.complete();
        });
        await startTls.future;
        if (dispose) {
          await client.dispose();
        } else {
          await client.disconnect();
        }
        expect(
          await join.timeout(const Duration(seconds: 1)),
          'Room connection cancelled.',
        );
      },
    );
  }
}
