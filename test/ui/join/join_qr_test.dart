import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/join/join_sheet.dart';
import 'package:meowwatch_mobile/ui/shared/invitation_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../home/ui_test_support.dart';
import 'scanner_test_support.dart';

const _invite =
    'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8999';

void main() {
  late MobileScannerPlatform previous;
  late TestScannerPlatform scanner;
  late UiTestApp fixture;
  setUp(() {
    previous = MobileScannerPlatform.instance;
    scanner = TestScannerPlatform();
    MobileScannerPlatform.instance = scanner;
    fixture = UiTestApp.create();
  });
  tearDown(() async {
    MobileScannerPlatform.instance = previous;
    await scanner.captures.close();
    await fixture.close();
  });

  testWidgets('scanning only fills review, even for repeated detections', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showJoinSheet(
                context,
                app: fixture.controller,
              ),
              child: const Text('Join'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    final scan = find.byKey(const Key('scan-room-invite-button'));
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.byType(InvitationScanner), findsOneWidget);
    scanner.emit('meowwatch-pair:not-a-room');
    await tester.pumpAndSettle();
    expect(find.textContaining('Use Nearby MeowWatch'), findsOneWidget);
    scanner.emit(_invite);
    scanner.emit(_invite);
    await tester.pumpAndSettle();

    expect(find.byType(InvitationScanner), findsNothing);
    await expectScannerReleased(tester, scanner, 1);
    expect(find.text('Room invitation received'), findsOneWidget);
    expect(find.text('Room: quiet-otter'), findsOneWidget);
    expect(find.text('Server: syncplay.pl:8999'), findsOneWidget);
    expect(find.text('Join this room'), findsOneWidget);
    expect(result, isNull);
    expect(fixture.controller.room, isNull);
    final submit = find.byKey(const Key('join-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result, _invite);
    expect(fixture.controller.room, isNull);
  });

  testWidgets('cancelled camera keeps typed input and can scan again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showJoinSheet(context, app: fixture.controller),
              child: const Text('Join'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('join-code-field'));
    await tester.enterText(field, 'saved-typed-room');
    for (var attempt = 0; attempt < 2; attempt++) {
      final scan = find.byKey(const Key('scan-room-invite-button'));
      await tester.ensureVisible(scan);
      await tester.tap(scan);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await expectScannerReleased(tester, scanner, attempt + 1);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'saved-typed-room',
      );
      expect(fixture.controller.room, isNull);
    }
    expect(scanner.starts, 2);
    expect(scanner.disposals, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
