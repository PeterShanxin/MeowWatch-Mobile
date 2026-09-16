import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// Regression for #40: the Syncplay server deduplicates colliding usernames by
/// appending a suffix ("meow" -> "meow_") and echoes the assigned name back in
/// its Hello reply. The client must adopt that name, otherwise our own identity
/// diverges from what peers (and the server's chat echo) call us — flipping
/// chat-bubble ownership and mislabelling the gear member list.
void main() {
  test('adopts the server-assigned username from the Hello reply', () async {
    final client = SyncplayClient();
    final states = <SyncConnectionState>[];
    final sub = client.connectionState.listen(states.add);

    client.debugHandleMessage(const HelloMessage(username: 'meow_'));
    await Future<void>.delayed(Duration.zero);

    expect(states.last.status, SyncConnectionStatus.connected);
    expect(states.last.username, 'meow_');

    await sub.cancel();
    await client.dispose();
  });

  test('treats the assigned name as self, not as a peer', () async {
    final client = SyncplayClient();
    final peers = <String>[];
    final sub = client.presence.listen((e) => peers.add(e.username));

    client.debugHandleMessage(const HelloMessage(username: 'meow_'));
    // Roster echoes us back under the assigned name alongside a real peer.
    client.debugHandleMessage(const RosterMessage(['meow_', 'lin']));
    await Future<void>.delayed(Duration.zero);

    // Only the genuine peer surfaces; 'meow_' is now us.
    expect(peers, ['lin']);

    await sub.cancel();
    await client.dispose();
  });

  test('a blank assigned username leaves the requested name intact', () async {
    final client = SyncplayClient();
    final states = <SyncConnectionState>[];
    final sub = client.connectionState.listen(states.add);

    client.debugMarkLoggedIn('lin');
    client.debugHandleMessage(const HelloMessage());
    await Future<void>.delayed(Duration.zero);

    expect(states.last.username, 'lin');

    await sub.cancel();
    await client.dispose();
  });

  // Regression for #93: a reconnect against a lingering ghost of our own
  // dropped session makes the server hand back a deduped name ("meow_"). The
  // PREVIOUS code adopted that name AND reused it for the next Hello, so each
  // reconnect added another "_" (meow -> meow_ -> meow__ …). The fix keeps the
  // originally requested name for every Hello.
  test(
    'reconnect re-requests the original name, not the assigned suffix',
    () async {
      final client = SyncplayClient();
      client.debugSeedIdentity('meow');

      // Server dedupes against our ghost and assigns a suffixed name.
      client.debugHandleMessage(const HelloMessage(username: 'meow_'));
      expect(
        client.debugRequestedUsername,
        'meow',
        reason: 'adopting the assigned name must not change what we request',
      );

      // The reconnect Hello must still ask for the clean original name.
      client.debugSendHello();
      final hellos = client.debugSentMessages
          .where((m) => m.containsKey('Hello'))
          .map((m) => (m['Hello'] as Map)['username'])
          .toList();
      expect(hellos.last, 'meow');

      await client.dispose();
    },
  );

  test('the suffix never compounds across repeated reconnects', () async {
    final client = SyncplayClient();
    client.debugSeedIdentity('meow');

    // Three drop/reconnect cycles, each time the server suffixing again.
    for (final assigned in ['meow_', 'meow_', 'meow_']) {
      client.debugSendHello();
      client.debugHandleMessage(HelloMessage(username: assigned));
    }

    final hellos = client.debugSentMessages
        .where((m) => m.containsKey('Hello'))
        .map((m) => (m['Hello'] as Map)['username'])
        .toList();
    // Every Hello asked for the clean name — no "meow__", "meow___", etc.
    expect(hellos, everyElement('meow'));

    await client.dispose();
  });

  // Codex review thread on #100: only the CURRENT server-assigned name is
  // reliably self. In the reconnect window a name the server suffixes is
  // indistinguishable between our own lingering ghost and a real user who took
  // our freed name — so the client must NOT guess by name. Any roster entry
  // whose name differs from our current identity is forwarded as a peer; the
  // ghost's downstream impact is contained in the UI (keyed peer files), not by
  // filtering names here. This locks in that a non-current name is never
  // swallowed, even when it equals a name we previously held.
  test(
    'only the current assigned name is filtered; an old name is forwarded',
    () async {
      final client = SyncplayClient();
      final peers = <String>[];
      final peerFiles = <PeerFile>[];
      final pSub = client.presence.listen((e) => peers.add(e.username));
      final fSub = client.peerFile.listen(peerFiles.add);

      // We held "meow", reconnected, and the server now calls us "meow_".
      client.debugSeedIdentity('meow');
      client.debugHandleMessage(const HelloMessage(username: 'meow_'));

      // Roster lists the holder of our old name ("meow", with a file) plus us.
      // The client can't know if "meow" is our ghost or a real reuser, so it
      // forwards it; only "meow_" (current self) is filtered.
      client.debugHandleMessage(
        const RosterMessage(
          ['meow', 'meow_'],
          files: [PeerFile(username: 'meow', name: 'whoever.mkv')],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(peers, ['meow']);
      expect(peerFiles.map((f) => f.username), ['meow']);

      await pSub.cancel();
      await fSub.cancel();
      await client.dispose();
    },
  );
}
