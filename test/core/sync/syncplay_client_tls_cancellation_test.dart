import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

void main() {
  test('manual leave closes TCP during a silent TLS handshake', () async {
    final peer = await _SilentTlsPeer.open();
    final client = SyncplayClient(livenessTimeout: const Duration(seconds: 3));
    addTearDown(() async {
      await client.dispose();
      await peer.dispose();
    });

    await _connect(client, peer.port);
    await peer.clientHello.future.timeout(const Duration(seconds: 2));
    expect(client.debugChannelSecure, isFalse);
    await client.disconnect();
    await peer.eof.future.timeout(const Duration(seconds: 1));
    expect(
      client.lastConnectionState?.status,
      SyncConnectionStatus.disconnected,
    );
    expect(peer.plaintext, contains('startTLS'));
    expect(peer.plaintext, isNot(contains('must-stay-secret')));
  });

  test('watchdog closes TCP during a silent TLS handshake', () async {
    final peer = await _SilentTlsPeer.open();
    final client = SyncplayClient(
      livenessTimeout: const Duration(milliseconds: 350),
    );
    addTearDown(() async {
      await client.dispose();
      await peer.dispose();
    });

    await _connect(client, peer.port);
    await peer.clientHello.future.timeout(const Duration(seconds: 2));
    await _until(
      () => client.lastConnectionState?.status == SyncConnectionStatus.error,
    );
    await peer.eof.future.timeout(const Duration(seconds: 1));
    expect(client.debugChannelSecure, isFalse);
    expect(client.debugReconnectScheduled, isFalse);
  });
}

Future<void> _connect(SyncplayClient client, int port) => client.connect(
  server: '127.0.0.1',
  port: port,
  username: 'probe',
  room: 'private-room',
  password: 'must-stay-secret',
);

final class _SilentTlsPeer {
  _SilentTlsPeer._(this._server);

  final ServerSocket _server;
  final sockets = <Socket>[];
  final clientHello = Completer<void>();
  final eof = Completer<void>();
  final plainBytes = <int>[];

  int get port => _server.port;
  String get plaintext => utf8.decode(plainBytes, allowMalformed: true);

  static Future<_SilentTlsPeer> open() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _SilentTlsPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  void _accept(Socket socket) {
    sockets.add(socket);
    var replied = false;
    socket.listen(
      (bytes) {
        if (!replied) {
          plainBytes.addAll(bytes);
          if (!plaintext.contains('startTLS')) return;
          replied = true;
          socket.add(utf8.encode('{"TLS":{"startTLS":"true"}}\r\n'));
        } else if (!clientHello.isCompleted) {
          clientHello.complete();
        }
      },
      onError: (Object _) {
        if (!eof.isCompleted) eof.complete();
      },
      onDone: () {
        if (!eof.isCompleted) eof.complete();
      },
    );
  }

  Future<void> dispose() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
