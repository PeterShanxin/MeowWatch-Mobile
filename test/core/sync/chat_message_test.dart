import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';

void main() {
  test('timestamp defaults to null and copyWith sets it', () {
    const m = ChatMessage(username: 'lin', text: 'hi');
    expect(m.timestamp, isNull);

    final t = DateTime(2026, 5, 28, 21, 43);
    final stamped = m.copyWith(timestamp: t);
    expect(stamped.timestamp, t);
    expect(stamped.username, 'lin');
    expect(stamped.text, 'hi');
  });

  test('equality includes timestamp', () {
    final t = DateTime(2026, 5, 28);
    expect(
      ChatMessage(username: 'a', text: 'x', timestamp: t),
      ChatMessage(username: 'a', text: 'x', timestamp: t),
    );
    expect(
      const ChatMessage(username: 'a', text: 'x'),
      isNot(ChatMessage(username: 'a', text: 'x', timestamp: t)),
    );
  });
}
