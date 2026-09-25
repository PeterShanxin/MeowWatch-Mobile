import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';

/// #199: `_debugSentMessages` records every outbound message in debug builds
/// and used to grow without bound — a slow, steady leak over a long debug
/// session. The buffer now keeps only the most recent
/// [SyncplayClient.debugSentMessagesCap] entries, dropping the oldest.
void main() {
  test(
    'debug sent-message buffer caps at the limit, dropping oldest first',
    () async {
      final client = SyncplayClient();
      client.debugMarkLoggedIn('meow');

      final cap = SyncplayClient.debugSentMessagesCap;
      for (var i = 0; i < cap + 50; i++) {
        client.sendChat('msg $i');
      }

      final sent = client.debugSentMessages;
      expect(sent, hasLength(cap));
      // Oldest 50 dropped: the buffer starts at msg 50 and ends at the newest.
      expect(sent.first['Chat'], 'msg 50');
      expect(sent.last['Chat'], 'msg ${cap + 49}');

      await client.dispose();
    },
  );

  test('buffer under the cap is untouched — nothing dropped early', () async {
    final client = SyncplayClient();
    client.debugMarkLoggedIn('meow');

    for (var i = 0; i < 10; i++) {
      client.sendChat('msg $i');
    }

    final sent = client.debugSentMessages;
    expect(sent, hasLength(10));
    expect(sent.first['Chat'], 'msg 0');

    await client.dispose();
  });
}
