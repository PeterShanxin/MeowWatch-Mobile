import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

void main() {
  late SyncplayClient client;

  setUp(() {
    client = SyncplayClient();
    client.debugMarkLoggedIn('me');
  });
  tearDown(() => client.dispose());

  void room(
    int milliseconds, {
    String? setter = 'peer',
    bool paused = false,
    bool seek = false,
  }) {
    client.debugHandleMessage(
      StateMessage(
        peer: PeerPlayState(
          position: Duration(milliseconds: milliseconds),
          paused: paused,
          doSeek: seek,
          setBy: setter,
        ),
      ),
    );
  }

  test('requires two advancing heartbeats from the same named peer', () {
    room(1000);
    expect(client.lastAdvancingRoomState, isNull);
    room(2000);
    expect(client.lastAdvancingRoomState?.position, const Duration(seconds: 2));
    room(3000, setter: 'other');
    expect(client.lastAdvancingRoomState, isNull);
    room(4000, setter: 'other');
    expect(client.lastAdvancingRoomState?.position, const Duration(seconds: 4));
  });

  test('self, pause, seek and stalled heartbeat revoke eligibility', () {
    room(1000);
    room(2000);
    expect(client.lastAdvancingRoomState, isNotNull);
    room(3000, setter: 'me');
    expect(client.lastAdvancingRoomState, isNull);
    room(4000);
    expect(client.lastAdvancingRoomState, isNull);
    room(5000);
    expect(client.lastAdvancingRoomState, isNotNull);
    room(5000, paused: true);
    expect(client.lastAdvancingRoomState, isNull);
    room(6000, seek: true);
    expect(client.lastAdvancingRoomState, isNull);
    room(7000);
    room(8000);
    expect(client.lastAdvancingRoomState, isNotNull);
    for (var i = 0; i < 4; i++) {
      room(8000);
    }
    expect(client.lastAdvancingRoomState, isNull);
  });

  test('own change handshake clears the correction heartbeat', () {
    room(1000);
    room(2000);
    expect(client.lastAdvancingRoomState, isNotNull);
    client.updateLocalState(
      position: const Duration(seconds: 2),
      paused: false,
    );
    client.notifyLocalChange(doSeek: false);
    room(3000);
    expect(client.lastAdvancingRoomState, isNull);
  });

  test(
    'small backward jitter retains only the old high-water sample',
    () async {
      room(1000);
      room(3100);
      room(4000);
      final advancing = client.lastAdvancingRoomState;
      expect(advancing?.position, const Duration(seconds: 4));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final oldAge = client.lastAdvancingRoomStateAge!;

      room(3650);
      expect(identical(client.lastAdvancingRoomState, advancing), isTrue);
      expect(client.lastAdvancingRoomStateAge!, greaterThanOrEqualTo(oldAge));
      room(4120);
      expect(
        client.lastAdvancingRoomState?.position,
        const Duration(milliseconds: 4120),
      );
    },
  );

  test('oscillation cannot refresh correction evidence forever', () {
    room(1000);
    room(3100);
    room(4000);
    final advancing = client.lastAdvancingRoomState;
    expect(advancing, isNotNull);
    for (final position in [3650, 4000, 3700, 4000]) {
      room(position);
    }
    expect(client.lastAdvancingRoomState, isNull);
  });

  test('a large setback revokes correction evidence', () {
    room(1000);
    room(3100);
    room(4000);
    expect(client.lastAdvancingRoomState, isNotNull);
    room(3400);
    expect(client.lastAdvancingRoomState, isNull);
    room(3500);
    expect(client.lastAdvancingRoomState, isNull);
    room(6200);
    expect(
      client.lastAdvancingRoomState?.position,
      const Duration(milliseconds: 6200),
    );
  });

  test('one large forward jump does not become a stable room clock', () {
    room(1000);
    room(3100);
    room(4000);
    expect(client.lastAdvancingRoomState, isNotNull);
    room(7500);
    expect(client.lastAdvancingRoomState, isNull);
    room(7600);
    expect(client.lastAdvancingRoomState, isNull);
  });

  test('recovery after stall needs real progress past the old mark', () {
    room(1000);
    room(3100);
    room(4000);
    for (var tick = 0; tick < 4; tick++) {
      room(4000);
    }
    expect(client.lastAdvancingRoomState, isNull);
    room(4800);
    expect(client.lastAdvancingRoomState, isNull);
    room(6200);
    expect(
      client.lastAdvancingRoomState?.position,
      const Duration(milliseconds: 6200),
    );
  });
}
