import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_files.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';

/// #93: a transient ghost of our own dropped session can briefly appear as an
/// extra peer after a fast reconnect. A single peer-file slot meant the ghost's
/// departure (or its file overwriting ours) made a friend who HAD loaded a
/// video read as "hasn't loaded". PeerFiles keys by username so that can't
/// happen.
void main() {
  const friend = PeerFile(username: 'lin', name: 'friend.mkv');
  const ghost = PeerFile(username: 'meow', name: 'mine.mkv');

  test('currentAmong returns a present peer\'s file', () {
    final book = const PeerFiles().set(friend);
    expect(book.currentAmong(['lin']), friend);
  });

  test('currentAmong ignores a file whose owner is not present', () {
    // The ghost's entry lingers, but it is no longer in the present set.
    final book = const PeerFiles().set(ghost);
    expect(book.currentAmong(['lin']), isNull);
  });

  test('removing one peer never wipes another peer\'s file (#93)', () {
    var book = const PeerFiles().set(ghost).set(friend);
    // The ghost departs; the friend's file must survive.
    book = book.remove('meow');
    expect(book.currentAmong(['lin']), friend);
  });

  test('a departed ghost stops masking the real friend (#93)', () {
    // Both present, ghost listed first. Friend has loaded; the hint must never
    // read "hasn't loaded" before OR after the ghost leaves.
    var book = const PeerFiles().set(ghost).set(friend);
    expect(book.currentAmong(['meow', 'lin']), isNotNull);
    book = book.remove('meow');
    expect(book.currentAmong(['lin']), friend);
  });

  test('set replaces the same user\'s prior file', () {
    const updated = PeerFile(username: 'lin', name: 'other.mkv');
    final book = const PeerFiles().set(friend).set(updated);
    expect(book.currentAmong(['lin']), updated);
  });

  test('operations are immutable — the original book is unchanged', () {
    final original = const PeerFiles().set(friend);
    final removed = original.remove('lin');
    expect(original.currentAmong(['lin']), friend);
    expect(removed.currentAmong(['lin']), isNull);
  });
}
