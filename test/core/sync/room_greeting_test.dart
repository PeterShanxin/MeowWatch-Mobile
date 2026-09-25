import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/room_greeting.dart';

void main() {
  group('roomGreeting', () {
    test('empty — you are first', () {
      expect(
        roomGreeting([]),
        "You're the first one here — waiting for friends…",
      );
    });

    test('one other member', () {
      expect(roomGreeting(['Alice']), 'Alice is in the room — say hi ~');
    });

    test('two other members', () {
      expect(
        roomGreeting(['Alice', 'Bob']),
        'Alice, Bob are in the room — say hi ~',
      );
    });

    test('three other members', () {
      expect(
        roomGreeting(['Alice', 'Bob', 'Charlie']),
        'Alice, Bob, Charlie are in the room — say hi ~',
      );
    });
  });
}
