import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/chat_store.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

import '../../support/syncplay_room_server.dart';

void main() {
  test(
    'two socket clients converge both ways and relay chat signals',
    () async {
      final server = await SyncplayRoomServer.start();
      final alice = SyncplayClient();
      final bob = SyncplayClient();
      final aliceChat = ChatStore(sync: alice, initialUsername: 'alice');
      final bobChat = ChatStore(sync: bob, initialUsername: 'bob');
      final appliedAlice = <PeerPlayState>[];
      final appliedBob = <PeerPlayState>[];
      for (final pair in [(alice, appliedAlice), (bob, appliedBob)]) {
        pair.$1.peerState.listen((state) {
          pair.$2.add(state);
          // The player boundary acknowledges the applied state before the next
          // heartbeat, without publishing it as a new local user command.
          pair.$1.updateLocalState(
            position: state.position,
            paused: state.paused,
          );
        });
      }
      addTearDown(() async {
        await aliceChat.dispose();
        await bobChat.dispose();
        await alice.dispose();
        await bob.dispose();
        await server.close();
      });
      await server.dial(alice, name: 'alice');
      await server.dial(bob, name: 'bob');

      alice.updateLocalState(
        position: const Duration(seconds: 37),
        paused: false,
      );
      alice.notifyLocalChange(doSeek: true);
      await _until(
        () => appliedBob.any((s) => !s.paused && s.position.inSeconds >= 37),
      );
      expect(server.roomSetBy, 'alice');
      // Give the first command's ignoringOnTheFly acknowledgement a round
      // trip before the other user issues a separate command.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      bob.updateLocalState(position: const Duration(seconds: 51), paused: true);
      bob.notifyLocalChange(doSeek: true);
      await _until(
        () => appliedAlice.any((s) => s.paused && s.position.inSeconds == 51),
      );
      expect(server.roomSetBy, 'bob');
      expect(server.roomPaused, isTrue);

      final incoming = bobChat.stream.firstWhere(
        (m) => m.any((m) => m.text == 'movie night'),
      );
      aliceChat.send('movie night');
      expect(
        (await incoming.timeout(const Duration(seconds: 3))).last.username,
        'alice',
      );
      final reaction = aliceChat.reactions.first;
      bobChat.sendReaction('❤️');
      expect((await reaction.timeout(const Duration(seconds: 3))).emoji, '❤️');
      final typing = bobChat.typing.first;
      aliceChat.sendTyping(isTyping: true);
      expect(
        (await typing.timeout(const Duration(seconds: 3))).isTyping,
        isTrue,
      );
      expect(bobChat.messages.where((m) => !m.system).length, 1);
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('peer did not converge');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
