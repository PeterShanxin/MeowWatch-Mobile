/// Build the system message shown when you join a room.
///
/// Empty [others] means the room was empty on arrival; ≥1 names lists who is
/// already present with appropriate is/are grammar.
String roomGreeting(List<String> others) {
  if (others.isEmpty) {
    return "You're the first one here — waiting for friends…";
  }
  final names = others.join(', ');
  final verb = others.length == 1 ? 'is' : 'are';
  return '$names $verb in the room — say hi ~';
}
