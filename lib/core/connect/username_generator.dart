import 'dart:math';

import 'room_code.dart';

/// Generates a friendly display name like `SleepyOtter` for someone who leaves
/// the username field blank (#172), instead of a bare hardcoded default.
///
/// Draws from the same curated word lists as the room-code generator
/// ([roomAdjectives] + [roomAnimals]) so the app keeps one voice — short, SFW,
/// easy to say aloud. 64 × 64 = 4,096 combinations; collisions are fine because
/// the Syncplay server already suffixes duplicate usernames.
///
/// Unlike room codes, a username carries no secrecy — it's shown to everyone in
/// the room — so a plain [Random] is enough; there is nothing to guess.
///
/// Pass a seeded [Random] in tests for deterministic output.
String generateUsername([Random? random]) {
  final r = random ?? Random();
  String pick(List<String> words) => words[r.nextInt(words.length)];
  String cap(String word) => word[0].toUpperCase() + word.substring(1);
  return '${cap(pick(roomAdjectives))}${cap(pick(roomAnimals))}';
}

/// The longest name [generateUsername] can ever emit, computed from the word
/// lists. Syncplay silently truncates usernames past 16 characters (upstream
/// `MAX_USERNAME_LENGTH`), which would desync the name the user saw from the
/// one peers see — so this MUST stay ≤16. A unit test guards it so growing a
/// word list can't silently break generated names.
int get maxGeneratedUsernameLength {
  int longest(List<String> words) => words.map((w) => w.length).reduce(max);
  return longest(roomAdjectives) + longest(roomAnimals);
}
