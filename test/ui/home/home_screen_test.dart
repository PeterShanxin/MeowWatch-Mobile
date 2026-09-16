import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/home/home_screen.dart';

import 'ui_test_support.dart';

void main() {
  testWidgets('small phone remains scrollable at 200% text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = UiTestApp.create();

    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: HomeScreen(
          app: fixture.controller,
          onJoin: () {},
          onSettings: () {},
          onUpgrade: () {},
          onStartRoom: () async {},
          onLocalMode: () async {},
          onResume: (_) async {},
        ),
      ),
    );

    expect(find.text('Movie night,\neven miles apart.'), findsOneWidget);
    final headline = tester.widget<Text>(
      find.text('Movie night,\neven miles apart.'),
    );
    expect(headline.style?.fontFamily, 'DMSerifDisplay');
    expect(headline.style?.fontSize, 40);
    expect(find.text('Local Player Mode'), findsOneWidget);
    expect(find.text('Pick a video. We’ll save your place.'), findsOneWidget);
    expect(find.byKey(const Key('home-scroll-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const Key('home-scroll-view')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(find.text('Continue Watching'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close();
  });

  testWidgets('tablet uses two columns and shows real resume context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = UiTestApp.create();
    final entry = WatchHistoryEntry(
      media: MediaItem(
        uri: Uri.parse('https://cdn.example.test/starlight.mp4'),
        title: 'Starlight Express',
      ),
      position: Duration(minutes: 14, seconds: 3),
      duration: Duration(hours: 1, minutes: 40),
      updatedAt: DateTime(2026, 9, 16),
      room: RoomTicket(
        id: 'history-room',
        isHost: false,
        config: RoomConfig(
          server: 'syncplay.pl',
          port: 8995,
          room: 'quiet-otter',
          username: 'Mochi',
        ),
      ),
    );
    await fixture.repository.record(entry);
    WatchHistoryEntry? resumed;

    await tester.pumpWidget(
      _app(
        child: HomeScreen(
          app: fixture.controller,
          onJoin: () {},
          onSettings: () {},
          onUpgrade: () {},
          onStartRoom: () async {},
          onLocalMode: () async {},
          onResume: (entry) async => resumed = entry,
        ),
      ),
    );

    expect(find.byKey(const Key('home-tablet-layout')), findsOneWidget);
    final headline = tester.widget<Text>(
      find.text('Movie night,\neven miles apart.'),
    );
    expect(headline.style?.fontSize, 52);
    expect(find.text('Starlight Express'), findsOneWidget);
    expect(find.text('Room quiet-otter · 14:03 of 1:40:00'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('resume-${entry.key}')));
    await tester.pump();
    expect(resumed, same(entry));
    expect(tester.takeException(), isNull);
    await fixture.close();
  });

  testWidgets('primary and secondary actions call their owner callbacks', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    var starts = 0;
    var joins = 0;
    var locals = 0;

    await tester.pumpWidget(
      _app(
        child: HomeScreen(
          app: fixture.controller,
          onJoin: () => joins++,
          onSettings: () {},
          onUpgrade: () {},
          onStartRoom: () async => starts++,
          onLocalMode: () async => locals++,
          onResume: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('start-room-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('join-room-button')));
    await tester.ensureVisible(find.byKey(const Key('local-mode-button')));
    await tester.tap(find.byKey(const Key('local-mode-button')));
    await tester.pump();
    expect((starts, joins, locals), (1, 1, 1));
    await fixture.close();
  });
}

Widget _app({required Widget child, double textScale = 1}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFEFB38C),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: child,
  );
}
