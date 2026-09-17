import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_code.dart';

void main() {
  // <adj>-<animal>-<verb>-<adj>-<noun>
  final magicSentence = RegExp(r'^[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+$');

  test('produces a five-word magic sentence', () {
    final code = generateRoomCode(Random(7));
    expect(code, matches(magicSentence));
  });

  test('is deterministic for a fixed seed', () {
    expect(generateRoomCode(Random(42)), generateRoomCode(Random(42)));
  });

  test('only ever draws from the published word lists', () {
    for (var seed = 0; seed < 200; seed++) {
      final parts = generateRoomCode(Random(seed)).split('-');
      // <adj> <animal> <verb> <adj> <noun>
      expect(parts.length, 5);
      expect(roomAdjectives, contains(parts[0]));
      expect(roomAnimals, contains(parts[1]));
      expect(roomVerbs, contains(parts[2]));
      expect(roomAdjectives, contains(parts[3]));
      expect(roomNouns, contains(parts[4]));
    }
  });

  test('every code stays within Syncplay\'s 35-char room-name limit', () {
    // Syncplay silently truncates room names past 35 chars, which would corrupt
    // the copied code and throw away entropy. The worst case (computed from the
    // word lists) must fit, so no draw can ever overflow.
    expect(maxGeneratedRoomCodeLength, lessThanOrEqualTo(35));
    for (var seed = 0; seed < 500; seed++) {
      expect(generateRoomCode(Random(seed)).length, lessThanOrEqualTo(35));
    }
  });

  test('code space comfortably blocks accidental or guessed joins', () {
    // The 35-char ceiling rules out the ~2e10 of the old random-suffix scheme
    // with real words, but the space must still dwarf any chance of a collision
    // or guess on an unlisted public room.
    expect(roomCodeCombinations, greaterThan(100000000)); // > 1e8
  });

  group('word lists are clean', () {
    for (final entry in <String, List<String>>{
      'adjectives': roomAdjectives,
      'animals': roomAnimals,
      'verbs': roomVerbs,
      'nouns': roomNouns,
    }.entries) {
      test('${entry.key} are unique, lowercase, and short', () {
        expect(
          entry.value.toSet().length,
          entry.value.length,
          reason: 'no duplicate ${entry.key}',
        );
        for (final word in entry.value) {
          // Letters only, ≤6 chars: easy to say aloud and keeps codes short
          // enough to never hit the 35-char room-name limit.
          expect(word, matches(RegExp(r'^[a-z]{1,6}$')), reason: word);
        }
      });
    }
  });
}
