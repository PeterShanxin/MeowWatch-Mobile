import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/session/room_invite.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/room/invite_sheet.dart';

import '../sheets/sheet_test_support.dart';

void main() {
  for (final endpoint in [
    (server: 'syncplay.pl', port: 8995),
    (server: 'syncplay.pl', port: 8998),
    (server: 'cinema.example.com', port: 9000),
  ]) {
    testWidgets('displayed and shared invites retain $endpoint', (
      tester,
    ) async {
      final app = createTestApp(billing: TestBilling())
        ..room = RoomTicket(
          id: 'invite-session',
          isHost: true,
          config: RoomConfig(
            server: endpoint.server,
            port: endpoint.port,
            room: 'cozy-cat-movie-night',
            username: 'Mochi',
          ),
        );
      Map<dynamic, dynamic>? shared;
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'share') shared = call.arguments as Map;
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showInviteSheet(context, app),
                  child: const Text('Invite'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      final manualCode = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final parsedCode = parseRoomInvite(manualCode, 'Friend');
      expect(parsedCode.room, app.room!.config.room);
      expect(parsedCode.server, endpoint.server);
      expect(parsedCode.port, endpoint.port);
      await tester.ensureVisible(find.text('Share invite'));
      await tester.tap(find.text('Share invite'));
      await tester.pumpAndSettle();
      expect(shared, isNotNull);
      // Android's SEND receiver accepts one URI, not a prose prefix or newline.
      final payload = shared!['text'] as String;
      expect(payload, app.invite.toString());
      expect(payload.contains(RegExp(r'\s')), isFalse);
      final parsedShare = parseRoomInvite(payload, 'Friend');
      expect(parsedShare.room, parsedCode.room);
      expect(parsedShare.server, parsedCode.server);
      expect(parsedShare.port, parsedCode.port);
      expect(shared!['subject'], 'Movie night? Join me on MeowWatch.');
      expect(tester.takeException(), isNull);
      await app.close();
    });
  }
}
