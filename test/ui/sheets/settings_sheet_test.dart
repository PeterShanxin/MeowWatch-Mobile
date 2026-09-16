import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/settings/settings_sheet.dart';

import 'sheet_test_support.dart';

void main() {
  testWidgets('saves display name and opens the supplied upgrade flow', (
    tester,
  ) async {
    final repository = TestRepository();
    final app = createTestApp(billing: TestBilling(), repository: repository);
    var upgradeCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSettingsSheet(
                context,
                app: app,
                onUpgrade: () => upgradeCalls++,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Luna');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(app.username, 'Luna');
    expect(repository.displayName, 'Luna');
    expect(find.text('Display name saved.'), findsOneWidget);

    await tester.ensureVisible(find.text('See Plus'));
    await tester.tap(find.text('See Plus'));
    await tester.pumpAndSettle();
    expect(upgradeCalls, 1);
    await app.close();
  });

  testWidgets('clears local watch history after confirmation', (tester) async {
    final repository = TestRepository();
    await repository.record(
      WatchHistoryEntry(
        media: MediaItem(
          uri: Uri.parse('https://cdn.example.com/movie.mp4'),
          title: 'Movie',
        ),
        position: const Duration(minutes: 2),
        duration: const Duration(minutes: 5),
        updatedAt: DateTime(2026, 9, 16),
      ),
    );
    final app = createTestApp(billing: TestBilling(), repository: repository);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showSettingsSheet(context, app: app, onUpgrade: () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Clear watch history'));
    await tester.tap(find.text('Clear watch history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear watch history?'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(repository.history, isEmpty);
    expect(find.text('Watch history cleared.'), findsOneWidget);
    expect(find.text('Watch history is empty'), findsOneWidget);
    await app.close();
  });

  testWidgets('restores Plus through the injected billing service', (
    tester,
  ) async {
    final billing = TestBilling()..grantOnRestore = true;
    final app = createTestApp(billing: billing);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showSettingsSheet(context, app: app, onUpgrade: () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restore purchases'));
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();

    expect(billing.configureCalls, 1);
    expect(billing.restoreCalls, 1);
    expect(find.text('Plus is active · unlimited hosting'), findsOneWidget);
    expect(find.text('Restored. MeowWatch Plus is active.'), findsOneWidget);
    await app.close();
  });

  testWidgets('does not silently rename an active room participant', (
    tester,
  ) async {
    final app = createTestApp(billing: TestBilling());
    app.room = const RoomTicket(
      id: 'active-room',
      config: RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'MEOW-ROOM',
        username: 'Mochi',
      ),
      isHost: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showSettingsSheet(context, app: app, onUpgrade: () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leave the current room'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save name'))
          .onPressed,
      isNull,
    );
    await app.close();
  });
}
