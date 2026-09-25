import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/session/room_invite.dart';

void main() {
  test('deep link pins the successful endpoint and preserves room', () {
    const config = RoomConfig(
      server: 'syncplay.pl',
      port: 8995,
      room: 'cozy-cat',
      username: 'Host',
    );
    final parsed = parseRoomInvite(
      encodeRoomInvite(config).toString(),
      'Guest',
    );
    expect(parsed.server, 'syncplay.pl');
    expect(parsed.port, 8995);
    expect(parsed.room, 'cozy-cat');
    expect(parsed.username, 'Guest');
    expect(parsed.endpointPolicy, SyncplayEndpointPolicy.pinned);
  });
  test('rejects malformed or truncated invitations', () {
    for (final value in [
      '',
      'meowwatch://join?room=test',
      'meowwatch://pair?room=test',
      'x' * 36,
      'bad\nroom',
    ]) {
      expect(() => parseRoomInvite(value, 'Guest'), throwsFormatException);
    }
  });
}
