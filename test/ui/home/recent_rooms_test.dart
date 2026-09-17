import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/home/home_screen.dart';

import 'ui_test_support.dart';

void main() {
  testWidgets('recent rooms use the newest video per room and stop at three', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    addTearDown(fixture.close);
    final olderRoomA = _entry(
      room: 'quiet-otter',
      title: 'Older room A video',
      uriSuffix: 'older-a',
      updatedAt: DateTime(2026, 9, 10),
    );
    final roomD = _entry(
      room: 'room-d',
      title: 'Room D video',
      uriSuffix: 'd',
      updatedAt: DateTime(2026, 9, 11),
    );
    final roomC = _entry(
      room: 'room-c',
      title: 'Room C video',
      uriSuffix: 'c',
      updatedAt: DateTime(2026, 9, 12),
    );
    final roomB = _entry(
      room: 'room-b',
      title: 'Room B video',
      uriSuffix: 'b',
      updatedAt: DateTime(2026, 9, 13),
    );
    final newestRoomA = _entry(
      room: 'quiet-otter',
      title: 'Newest room A video',
      uriSuffix: 'newer-a',
      updatedAt: DateTime(2026, 9, 14),
    );
    final local = WatchHistoryEntry(
      media: MediaItem(
        uri: Uri.parse('https://cdn.example.test/local.mp4'),
        title: 'Local-only video',
      ),
      position: const Duration(minutes: 2),
      duration: const Duration(minutes: 20),
      updatedAt: DateTime(2026, 9, 15),
    );
    for (final entry in [olderRoomA, roomD, roomC, roomB, newestRoomA, local]) {
      await fixture.repository.record(entry);
    }
    WatchHistoryEntry? watchedAgain;

    await tester.pumpWidget(
      _app(
        HomeScreen(
          app: fixture.controller,
          onJoin: () {},
          onSettings: () {},
          onUpgrade: () {},
          onStartRoom: () async {},
          onLocalMode: () async {},
          onResume: (_) async {},
          onWatchAgain: (entry) async => watchedAgain = entry,
        ),
      ),
    );

    expect(find.text('Recent rooms'), findsOneWidget);
    expect(find.text('Start a new room with this video.'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('watch-again-syncplay.pl:8995/quiet-otter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('watch-again-syncplay.pl:8995/room-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('watch-again-syncplay.pl:8995/room-c')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('watch-again-syncplay.pl:8995/room-d')),
      findsNothing,
    );

    final roomACard = find.byKey(
      const ValueKey('watch-again-syncplay.pl:8995/quiet-otter'),
    );
    expect(
      find.descendant(
        of: roomACard,
        matching: find.text('Newest room A video'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: roomACard, matching: find.text('Older room A video')),
      findsNothing,
    );
    await tester.ensureVisible(roomACard);
    await tester.tap(roomACard);
    await tester.pump();
    expect(watchedAgain, same(newestRoomA));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('recent rooms remain scrollable on phone and tablet layouts', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    addTearDown(fixture.close);
    for (var index = 0; index < 3; index++) {
      await fixture.repository.record(
        _entry(
          room: 'room-$index',
          title: 'A deliberately long shared video title number $index',
          uriSuffix: '$index',
          updatedAt: DateTime(2026, 9, 13 + index),
        ),
      );
    }

    Future<void> pumpAt(Size size, double textScale) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          HomeScreen(
            app: fixture.controller,
            onJoin: () {},
            onSettings: () {},
            onUpgrade: () {},
            onStartRoom: () async {},
            onLocalMode: () async {},
            onResume: (_) async {},
            onWatchAgain: (_) async {},
          ),
          textScale: textScale,
        ),
      );
      expect(find.byKey(const Key('home-scroll-view')), findsOneWidget);
      expect(find.text('Recent rooms'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Recent rooms'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpAt(const Size(320, 568), 2);
    await pumpAt(const Size(800, 1280), 1);
    expect(find.byKey(const Key('home-tablet-layout')), findsOneWidget);
    await pumpAt(const Size(800, 1280), 2);
    expect(find.byKey(const Key('home-tablet-layout')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });
}

WatchHistoryEntry _entry({
  required String room,
  required String title,
  required String uriSuffix,
  required DateTime updatedAt,
}) => WatchHistoryEntry(
  media: MediaItem(
    uri: Uri.parse('https://cdn.example.test/$uriSuffix.mp4'),
    title: title,
  ),
  position: const Duration(minutes: 12),
  duration: const Duration(hours: 1, minutes: 20),
  updatedAt: updatedAt,
  room: RoomTicket(
    id: 'ticket-$room-$uriSuffix',
    isHost: true,
    config: RoomConfig(
      server: 'syncplay.pl',
      port: 8995,
      room: room,
      username: 'Mochi',
    ),
  ),
);

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
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
