/// The transient over-video banner shown when you arrive in a room that already
/// has friends in it — the visible counterpart to `roomGreeting`'s chat line, so
/// a friend who was already present is announced on screen too, not only in chat
/// (easy to miss).
///
/// Empty [others] means you're first in: there's no one to announce, so the
/// "waiting for a friend" hint carries it and this stays null.
String? rosterPresenceBanner(List<String> others) {
  if (others.isEmpty) return null;
  final names = others.join(', ');
  final verb = others.length == 1 ? 'is' : 'are';
  return '🐾 $names $verb here';
}
