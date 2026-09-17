import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/sync_messages.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// The client emits a single [initialRoster] event on the first roster reply
/// (issue #90). Subsequent roster replies (e.g. after announceFile) are silent.
void main() {
  late SyncplayClient client;

  setUp(() {
    client = SyncplayClient();
    client.debugMarkLoggedIn('me');
  });

  tearDown(() => client.dispose());

  test('first roster emits initialRoster with other members', () async {
    final events = <List<String>>[];
    client.initialRoster.listen(events.add);

    client.debugHandleMessage(const RosterMessage(['me', 'Alice', 'Bob']));
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single, ['Alice', 'Bob']);
  });

  test('empty room emits initialRoster with empty list', () async {
    final events = <List<String>>[];
    client.initialRoster.listen(events.add);

    client.debugHandleMessage(const RosterMessage(['me']));
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single, isEmpty);
  });

  test('second roster reply (after announceFile) does not re-emit', () async {
    final events = <List<String>>[];
    client.initialRoster.listen(events.add);

    client.debugHandleMessage(const RosterMessage(['me', 'Alice']));
    // Simulates the roster reply that comes back after announceFile.
    client.debugHandleMessage(const RosterMessage(['me', 'Alice']));
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
  });
}
