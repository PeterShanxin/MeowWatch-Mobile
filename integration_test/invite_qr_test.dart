import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/session/room_invite.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/join/join_sheet.dart';

import 'support/native_invite_qr.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native QR image decoding reaches explicit room review',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final app = await openAppServices();
      try {
        final room = RoomConfig(
          room: 'Movie night 一起看',
          server: 'syncplay.pl',
          port: 8999,
          username: app.username,
        );
        final encoded = encodeRoomInvite(room).toString();
        final decoded = await decodeGeneratedInviteQr(encoded);
        expect(decoded, encoded);
        // A second independent native decode also verifies controller cleanup.
        expect(await decodeGeneratedInviteQr(encoded), encoded);
        String? accepted;
        await tester.pumpWidget(
          MaterialApp(
            theme: meowWatchTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => accepted = await showJoinSheet(
                    context,
                    app: app,
                    initialInvite: decoded,
                  ),
                  child: const Text('Review decoded invite'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Review decoded invite'));
        await tester.pumpAndSettle();
        expect(find.text('Room: ${room.room}'), findsOneWidget);
        expect(find.text('Server: syncplay.pl:8999'), findsOneWidget);
        expect(accepted, isNull);
        expect(app.room, isNull);
        final confirm = find.byKey(const Key('join-submit-button'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(accepted, encoded);
        expect(app.room, isNull);
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['inviteQr'] = {
          'result': 'passed',
          'runtime': Platform.operatingSystemVersion,
          'verified': [
            'generated_qr_png_decoded_by_android_mlkit',
            'second_decode_after_controller_disposal',
            'exact_room_and_nondefault_endpoint_preserved',
            'decoded_invitation_requires_explicit_confirmation',
          ],
          'cameraHardwareEvidence': false,
          'networkJoinEvidence': false,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
