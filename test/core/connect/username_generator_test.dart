import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_code.dart';
import 'package:meowwatch_mobile/core/connect/username_generator.dart';

void main() {
  test('same seed generates the same username', () {
    expect(generateUsername(Random(42)), generateUsername(Random(42)));
  });

  test(
    'reads as CapitalizedAdjective+CapitalizedAnimal from the room lists',
    () {
      for (var seed = 0; seed < 200; seed++) {
        final name = generateUsername(Random(seed));
        final match = RegExp(r'^([A-Z][a-z]+)([A-Z][a-z]+)$').firstMatch(name);
        expect(
          match,
          isNotNull,
          reason: '"$name" is not two capitalized words',
        );
        expect(roomAdjectives, contains(match!.group(1)!.toLowerCase()));
        expect(roomAnimals, contains(match.group(2)!.toLowerCase()));
      }
    },
  );

  test('worst case stays within the Syncplay username cap', () {
    // Upstream MAX_USERNAME_LENGTH = 16; the server silently truncates past
    // it, which would desync the name the user saw from the one peers see.
    expect(maxGeneratedUsernameLength, lessThanOrEqualTo(16));
  });
}
