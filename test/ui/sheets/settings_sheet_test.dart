import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/settings/settings_sheet.dart';

import 'sheet_test_support.dart';

void main() {
  testWidgets(
    'upgrade waits for the owned settings route to finish exiting',
    (tester) async {
      final app = createTestApp(billing: TestBilling());
      try {
        var upgrades = 0;
        var completed = false;
        await _openSettings(
          tester,
          app: app,
          onUpgrade: () {
            expect(completed, isTrue);
            expect(find.text('Settings', skipOffstage: false), findsNothing);
            upgrades++;
          },
        );
        final route = ModalRoute.of(tester.element(find.text('Settings')))!;
        route.completed.then((_) => completed = true);
        await tester.ensureVisible(find.text('See Plus'));
        await tester.tap(find.text('See Plus'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(completed, isFalse);
        expect(upgrades, 0);
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(upgrades, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      }
    },
    semanticsEnabled: true,
  );

  testWidgets('closing settings does not request an upgrade', (tester) async {
    final app = createTestApp(billing: TestBilling());
    try {
      var upgrades = 0;
      await _openSettings(tester, app: app, onUpgrade: () => upgrades++);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(upgrades, 0);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Open settings'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.close();
    }
  });

  for (final interruption in ['new page', 'dialog', 'unmount']) {
    testWidgets(
      'settings upgrade stops after $interruption during its exit',
      (tester) async {
        final app = createTestApp(billing: TestBilling());
        try {
          final navigator = GlobalKey<NavigatorState>();
          var upgrades = 0;
          await _openSettings(
            tester,
            app: app,
            navigatorKey: navigator,
            onUpgrade: () => upgrades++,
          );
          await tester.ensureVisible(find.text('See Plus'));
          final upgrade = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'See Plus'),
              )
              .onPressed!;
          await tester.tap(find.text('See Plus'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(upgrades, 0);
          if (interruption == 'new page') {
            navigator.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other page')),
              ),
            );
          } else if (interruption == 'dialog') {
            showDialog<void>(
              context: navigator.currentContext!,
              builder: (_) => const AlertDialog(title: Text('Other dialog')),
            );
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          // A queued tap on the retiring sheet must not dismiss a newer route.
          upgrade();
          await tester.pumpAndSettle();
          expect(upgrades, 0);
          expect(find.text('Settings', skipOffstage: false), findsNothing);
          if (interruption != 'unmount') {
            expect(
              find.text(
                interruption == 'new page' ? 'Other page' : 'Other dialog',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await app.close();
        }
      },
      semanticsEnabled: true,
    );
  }

  testWidgets(
    'covered settings cannot pop a dialog or open appearance',
    (tester) async {
      final app = createTestApp(billing: TestBilling());
      try {
        final navigator = GlobalKey<NavigatorState>();
        var upgrades = 0;
        await _openSettings(
          tester,
          app: app,
          navigatorKey: navigator,
          onUpgrade: () => upgrades++,
        );
        final upgrade = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'See Plus'))
            .onPressed!;
        final appearance = tester
            .widget<OutlinedButton>(
              find.byKey(const Key('choose-appearance-button')),
            )
            .onPressed!;
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Other dialog')),
        );
        await tester.pumpAndSettle();
        upgrade();
        appearance();
        await tester.pumpAndSettle();
        expect(upgrades, 0);
        expect(find.text('Other dialog'), findsOneWidget);
        expect(find.text('Settings', skipOffstage: false), findsOneWidget);
        expect(find.byKey(const Key('theme-choice-cozy')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      }
    },
    semanticsEnabled: true,
  );

  testWidgets('replaying the guide leaves an active session and data alone', (
    tester,
  ) async {
    final repository = TestRepository();
    final billing = TestBilling();
    final app = createTestApp(billing: billing, repository: repository);
    const ticket = RoomTicket(
      id: 'existing-room',
      config: RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'MEOW-ROOM',
        username: 'Mochi',
      ),
      isHost: true,
    );
    app.room = ticket;
    repository.activeRoom = ticket;
    final target = app.target;
    final snapshot = target.snapshot;
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
    for (var replay = 0; replay < 2; replay++) {
      final guide = find.byKey(const Key('settings-quick-guide-button'));
      await tester.ensureVisible(guide);
      await tester.tap(guide);
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3'), findsOneWidget);
      final next = find.byKey(const Key('quick-guide-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-guide-close')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Settings'), findsOneWidget);
    expect(app.room, same(ticket));
    expect(repository.activeRoom, same(ticket));
    expect(repository.saves, 0);
    expect(repository.displayName, 'Mochi');
    expect(app.target, same(target));
    expect(app.target.snapshot, same(snapshot));
    expect(billing.configureCalls, 0);
    expect(billing.purchaseCalls, 0);
    await app.close();
  });

  testWidgets('opens About, privacy and licenses from settings', (
    tester,
  ) async {
    final app = createTestApp(billing: TestBilling());
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
    final about = find.byKey(const Key('about-privacy-licenses-button'));
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(find.text('About MeowWatch'), findsOneWidget);
    expect(find.text('Together Rooms'), findsOneWidget);
    expect(find.text('RevenueCat'), findsOneWidget);
    expect(find.text('Nearby MeowWatch'), findsOneWidget);
    await app.close();
  });

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

  for (final alreadyConfigured in [false, true]) {
    testWidgets(
      'restore failure is shown with cached Plus (configured: $alreadyConfigured)',
      (tester) async {
        final billing = TestBilling(plus: true)
          ..restoreResult = const BillingResult(
            BillingStatus.failure,
            message:
                'The store could not complete this request. Please try again.',
          );
        if (alreadyConfigured) await billing.configure();
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

        expect(billing.restoreCalls, 1);
        expect(billing.isPlus, isTrue);
        expect(find.text('Restored. MeowWatch Plus is active.'), findsNothing);
        expect(find.text(billing.restoreResult.message!), findsOneWidget);
        await app.close();
      },
    );
  }

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

Future<void> _openSettings(
  WidgetTester tester, {
  required AppController app,
  required VoidCallback onUpgrade,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showSettingsSheet(context, app: app, onUpgrade: onUpgrade),
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}
