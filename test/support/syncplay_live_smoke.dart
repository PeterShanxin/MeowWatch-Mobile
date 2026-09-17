// Explicit network smoke: dart run test/support/syncplay_live_smoke.dart
// This creates a short-lived, randomly named public room and closes both peers.
import 'dart:async';
import 'dart:io';

import 'package:meowwatch_mobile/core/chat/chat_store.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_discovery.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

Future<void> main() async {
  final room = 'mobile-smoke-${DateTime.now().microsecondsSinceEpoch}';
  final config = RoomConfig(
    server: 'syncplay.pl',
    port: 8995,
    room: room,
    username: 'mobile-a',
    endpointPolicy: SyncplayEndpointPolicy.discover,
  );
  SyncplayClient? alice;
  final bob = SyncplayClient();
  ChatStore? aChat;
  ChatStore? bChat;
  try {
    final outcome = await joinFirstWorkingEndpoint(
      config: config,
      settings: MemoryEndpointSettings(),
      createClient: () =>
          SyncplayClient(livenessTimeout: const Duration(seconds: 8)),
      connectUntilJoin: (client, endpoint) => client.connectUntilJoin(
        server: endpoint.host,
        port: endpoint.port,
        room: room,
        username: 'mobile-a',
      ),
    );
    final join = outcome.join;
    if (join == null) throw StateError(outcome.error ?? 'No endpoint');
    alice = join.client;
    aChat = ChatStore(sync: alice, initialUsername: alice.username);
    bChat = ChatStore(sync: bob, initialUsername: 'mobile-b');
    final aStates = <PeerPlayState>[];
    final bStates = <PeerPlayState>[];
    for (final pair in [(alice, aStates), (bob, bStates)]) {
      pair.$1.peerState.listen((s) {
        pair.$2.add(s);
        pair.$1.updateLocalState(position: s.position, paused: s.paused);
      });
    }
    final roster = bob.initialRoster.first;
    final presence = alice.presence.firstWhere(
      (event) =>
          event.username == 'mobile-b' && event.kind == PresenceKind.joined,
    );
    final error = await bob.connectUntilJoin(
      server: join.endpoint.host,
      port: join.endpoint.port,
      room: room,
      username: 'mobile-b',
    );
    if (error != null) throw StateError(error);
    if (!(await roster.timeout(
      const Duration(seconds: 10),
    )).contains(alice.username)) {
      throw StateError('Initial roster omitted the other client');
    }
    await presence.timeout(const Duration(seconds: 10));
    stdout.writeln('PASS secure Hello for two clients on ${join.endpoint}');
    stdout.writeln('PASS initial roster and peer presence');
    alice.announceFile(
      name: 'mobile-protocol-smoke.mp4',
      size: 1024,
      duration: const Duration(minutes: 5),
    );
    bob.announceFile(
      name: 'mobile-protocol-smoke.mp4',
      size: 1024,
      duration: const Duration(minutes: 5),
    );
    alice.updateLocalState(
      position: const Duration(seconds: 42),
      paused: false,
    );
    alice.notifyLocalChange(doSeek: true);
    await until(
      () => bStates.any((s) => !s.paused && s.position.inSeconds >= 42),
    );
    bob.updateLocalState(position: const Duration(seconds: 68), paused: true);
    bob.notifyLocalChange(doSeek: true);
    await until(
      () => aStates.any((s) => s.paused && s.position.inSeconds == 68),
    );
    stdout.writeln('PASS bidirectional play/pause/seek');
    final message = bChat.stream.firstWhere(
      (m) => m.any((m) => m.text == 'mobile smoke'),
    );
    aChat.send('mobile smoke');
    await message.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(seconds: 2));
    final reaction = aChat.reactions.first;
    bChat.sendReaction('❤️');
    await reaction.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(seconds: 2));
    final typing = bChat.typing.first;
    aChat.sendTyping(isTyping: true);
    if (!(await typing.timeout(const Duration(seconds: 10))).isTyping) {
      throw StateError('typing signal not received');
    }
    stdout.writeln('PASS chat/reaction/typing on real encrypted sockets');
    final recovered = bob.connectionState.firstWhere(
      (state) => state.status == SyncConnectionStatus.connected,
    );
    // Close a real live socket through the same path used by the watchdog.
    // This verifies secure redial, not mobile radio/network-loss handling.
    bob.debugSimulateConnectionLost();
    await recovered.timeout(const Duration(seconds: 20));
    stdout.writeln('PASS secure reconnect after forced socket teardown');
  } catch (error, stack) {
    stderr.writeln('FAIL $error\n$stack');
    exitCode = 1;
  } finally {
    await aChat?.dispose();
    await bChat?.dispose();
    await alice?.dispose();
    await bob.dispose();
  }
}

Future<void> until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('No peer convergence');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
