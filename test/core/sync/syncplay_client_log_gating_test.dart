import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

void main() {
  test('quiet logging skips raw traffic and no-op FOLLOW formatting', () async {
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => !verboseOnly,
    );
    addTearDown(client.dispose);
    client.debugMarkLoggedIn('me');
    client.updateLocalState(position: Duration.zero, paused: true);

    client.debugReceiveChunk(
      utf8.encode(
        '${json.encode({
          'State': {
            'playstate': {'position': 0.0, 'paused': true, 'doSeek': false, 'setBy': 'peer'},
            'ping': <String, Object?>{},
          },
        })}\r\n',
      ),
    );

    expect(logs.where((line) => line.startsWith('<<')), isEmpty);
    expect(logs.where((line) => line.startsWith('FOLLOW')), isEmpty);
  });

  test('quiet logging keeps an applied FOLLOW decision', () async {
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => !verboseOnly,
    );
    addTearDown(client.dispose);
    client.debugMarkLoggedIn('me');
    client.updateLocalState(position: Duration.zero, paused: true);

    client.debugHandleMessage(
      const StateMessage(
        peer: PeerPlayState(
          position: Duration(seconds: 5),
          paused: false,
          doSeek: true,
          setBy: 'peer',
        ),
      ),
    );

    expect(
      logs.where((line) => line.startsWith('FOLLOW')),
      contains(contains('apply=true')),
    );
  });

  test('quiet logging keeps and redacts an inbound Error line', () async {
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => !verboseOnly,
    );
    addTearDown(client.dispose);

    client.debugReceiveChunk(
      utf8.encode(
        '${json.encode({
          'Error': {'message': 'bad https://user:token@cdn.example/clip.mp4?sig=secret'},
        })}\r\n',
      ),
    );

    final raw = logs.singleWhere((line) => line.startsWith('<<'));
    expect(raw, contains('https://cdn.example/clip.mp4'));
    expect(raw, isNot(contains('user:token')));
    expect(raw, isNot(contains('sig=secret')));
  });

  test('verbose raw logging still redacts URL credentials', () async {
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => true,
    );
    addTearDown(client.dispose);

    client.debugReceiveChunk(
      utf8.encode(
        '${json.encode({
          'Chat': {'username': 'peer', 'message': 'https://user:token@cdn.example/clip.mp4?sig=secret#fragment'},
        })}\r\n',
      ),
    );

    final raw = logs.singleWhere((line) => line.startsWith('<<'));
    expect(raw, contains('https://cdn.example/clip.mp4'));
    expect(raw, isNot(contains('user:token')));
    expect(raw, isNot(contains('sig=secret')));
    expect(raw, isNot(contains('fragment')));
  });

  test('quiet logging skips outbound raw formatting', () async {
    final sockets = await _openSocketPair();
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => !verboseOnly,
    );
    addTearDown(() async {
      await client.dispose();
      await sockets.close();
    });
    client.debugAttachLoggedInSocket(sockets.client, username: 'me');

    client.sendChat('hello');

    expect(logs.where((line) => line.startsWith('>>')), isEmpty);
  });

  test('verbose outbound logging still redacts URL credentials', () async {
    final sockets = await _openSocketPair();
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => true,
    );
    addTearDown(() async {
      await client.dispose();
      await sockets.close();
    });
    client.debugAttachLoggedInSocket(sockets.client, username: 'me');

    client.sendChat(
      'watch https://user:token@cdn.example/clip.mp4?sig=secret#fragment',
    );

    final raw = logs.singleWhere((line) => line.startsWith('>>'));
    expect(raw, contains('https://cdn.example/clip.mp4'));
    expect(raw, isNot(contains('user:token')));
    expect(raw, isNot(contains('sig=secret')));
    expect(raw, isNot(contains('fragment')));
  });

  test('logging off skips applied FOLLOW and inbound Error formatting', () {
    final logs = <String>[];
    final client = SyncplayClient(
      onLog: logs.add,
      shouldLog: ({required verboseOnly}) => false,
    );
    addTearDown(client.dispose);
    client.debugMarkLoggedIn('me');
    client.updateLocalState(position: Duration.zero, paused: true);

    client.debugHandleMessage(
      const StateMessage(
        peer: PeerPlayState(
          position: Duration(seconds: 5),
          paused: false,
          doSeek: true,
          setBy: 'peer',
        ),
      ),
    );
    client.debugReceiveChunk(
      utf8.encode('{"Error":{"message":"bad password"}}\r\n'),
    );

    expect(logs, isEmpty);
  });
}

class _SocketPair {
  const _SocketPair(this.server, this.client, this.peer);

  final ServerSocket server;
  final Socket client;
  final Socket peer;

  Future<void> close() async {
    client.destroy();
    peer.destroy();
    await server.close();
  }
}

Future<_SocketPair> _openSocketPair() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = Completer<Socket>();
  server.listen(accepted.complete);
  final client = await Socket.connect(
    InternetAddress.loopbackIPv4,
    server.port,
  );
  return _SocketPair(server, client, await accepted.future);
}
