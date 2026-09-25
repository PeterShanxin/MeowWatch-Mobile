import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// The local user's own play/pause/seek must surface as a [SyncActivity] on the
/// `activity` stream (issue #27). The Syncplay client classifies the change in
/// `notifyLocalChange`, comparing the new local state against the prior one it
/// has been fed via `updateLocalState`.
void main() {
  late SyncplayClient client;
  late List<SyncActivity> events;

  setUp(() {
    client = SyncplayClient();
    events = <SyncActivity>[];
    client.activity.listen(events.add);
  });

  tearDown(() => client.dispose());

  test('local pause is announced with our username and position', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: true,
    );
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.kind, SyncActivityKind.paused);
    expect(events.single.username, 'me');
    expect(events.single.position, const Duration(seconds: 30));
  });

  test('local resume (play) is announced as played', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: true,
    );
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: false,
    );
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.kind, SyncActivityKind.played);
  });

  test('local forward seek is announced at the landing position', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(
      position: const Duration(seconds: 10),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 90),
      paused: false,
    );
    client.notifyLocalChange(doSeek: true);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.kind, SyncActivityKind.seekedForward);
    expect(events.single.position, const Duration(seconds: 90));
  });

  test('local seek marks the next heartbeat with doSeek', () {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(
      position: const Duration(seconds: 10),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 90),
      paused: false,
    );
    client.notifyLocalChange(doSeek: true);

    client.debugHandleMessage(const StateMessage());

    final state = client.debugSentMessages.single['State']! as Map;
    final playstate = state['playstate']! as Map;
    expect(playstate['position'], 90.0);
    expect(playstate['paused'], false);
    expect(playstate['doSeek'], true);
  });

  test('a live Local -> Synced adopt still asserts position on syncplay.pl\'s '
      'first forced State', () {
    // adoptOpenSource queues the change BEFORE connect. syncplay.pl's first
    // State after Hello is the empty-room forced update (0:00 paused, doSeek,
    // serverIgnore, no setBy). That reply is the only chance the room moves.
    client.updateLocalState(position: const Duration(minutes: 5), paused: true);
    client.notifyLocalChange(doSeek: true);

    client.debugHandleMessage(const HelloMessage(username: 'host'));
    client.debugHandleMessage(
      const StateMessage(
        peer: PeerPlayState(
          position: Duration.zero,
          paused: true,
          doSeek: true,
        ),
        serverIgnore: 1,
      ),
    );

    final states = client.debugSentMessages
        .where((m) => m['State'] is Map)
        .map((m) => (m['State'] as Map)['playstate'] as Map)
        .toList();
    expect(states, isNotEmpty);
    expect(
      states.first['position'],
      300.0,
      reason:
          'the first reply after Hello must carry the adopted position, '
          'not the empty-room 0:00',
    );
    expect(states.first['paused'], isTrue);
    expect(
      states.first['doSeek'],
      isTrue,
      reason: 'a Syncplay room only moves on a signalled change',
    );
  });

  test('local backward seek is announced as seekedBack', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(
      position: const Duration(seconds: 90),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 10),
      paused: false,
    );
    client.notifyLocalChange(doSeek: true);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.kind, SyncActivityKind.seekedBack);
    expect(events.single.position, const Duration(seconds: 10));
  });

  test(
    'a zero-delta seek resolves to seekedForward (non-negative delta)',
    () async {
      client.debugMarkLoggedIn('me');
      client.updateLocalState(
        position: const Duration(seconds: 50),
        paused: false,
      );
      client.updateLocalState(
        position: const Duration(seconds: 50),
        paused: false,
      );
      client.notifyLocalChange(doSeek: true);
      await Future<void>.delayed(Duration.zero);
      expect(events.single.kind, SyncActivityKind.seekedForward);
    },
  );

  test('nothing announced for a logged-in but empty username', () async {
    client.debugMarkLoggedIn('');
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: true,
    );
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('nothing announced before login (no username to attribute)', () async {
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: false,
    );
    client.updateLocalState(
      position: const Duration(seconds: 30),
      paused: true,
    );
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });
}
