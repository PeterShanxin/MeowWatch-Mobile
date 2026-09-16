import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';

import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'DMSans': 'assets/fonts/DMSans.ttf',
      'DMSerifDisplay': 'assets/fonts/DMSerifDisplay.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets('small phone transport controls reflow at 200% text', (
    tester,
  ) async {
    await _setView(tester, const Size(360, 640));
    final fixture = UiTestApp.create();
    final target = fixture.controller.phone as SyncTestTarget;
    target.emit(
      PlaybackSnapshot(
        media: MediaItem(
          uri: Uri.parse('https://example.test/a-very-long-film.mp4'),
          title: 'A Very Long Film',
        ),
        position: const Duration(hours: 12, minutes: 34, seconds: 56),
        duration: const Duration(hours: 99, minutes: 59, seconds: 59),
        connection: PlaybackConnection.ready,
      ),
    );
    await fixture.controller.useLocalMode();
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        captureKey: capture,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Back to home'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('12:34:56'), findsOneWidget);
    expect(find.text('99:59:59'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-small-phone-player');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('short landscape keeps actions and transport usable at 200%', (
    tester,
  ) async {
    await _setView(tester, const Size(800, 360));
    final fixture = UiTestApp.create();
    await fixture.controller.useLocalMode();
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        captureKey: capture,
      ),
    );
    await tester.pump();

    expect(find.text('Choose a video'), findsOneWidget);
    expect(find.text('Watch together'), findsOneWidget);
    expect(find.byTooltip('Play together'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-landscape-player');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('chat sheet fits a short landscape viewport above the keyboard', (
    tester,
  ) async {
    await _setView(
      tester,
      const Size(800, 360),
      viewInsets: const FakeViewPadding(bottom: 180),
    );
    final fixture = UiTestApp.create();
    fixture.controller.connection = const SyncConnectionState(
      status: SyncConnectionStatus.reconnecting,
    );
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showChatSheet(context, fixture.controller),
            child: const Text('Open chat'),
          ),
        ),
        captureKey: capture,
      ),
    );
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close chat'), findsOneWidget);
    expect(find.text('Chat unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-landscape-keyboard-chat');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('connected empty chat has an accessible invitation', (
    tester,
  ) async {
    await _setView(tester, const Size(360, 640));
    final fixture = UiTestApp.create();
    fixture.controller.connection = const SyncConnectionState(
      status: SyncConnectionStatus.connected,
    );

    await tester.pumpWidget(
      _scaledApp(ChatPanel(app: fixture.controller), textScale: 1),
    );

    expect(find.text('No messages yet. Say hello.'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });
}

Future<void> _setView(
  WidgetTester tester,
  Size size, {
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = viewInsets;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Widget _scaledApp(
  Widget child, {
  double textScale = 2,
  GlobalKey? captureKey,
}) => RepaintBoundary(
  key: captureKey,
  child: MaterialApp(
    theme: meowWatchTheme(),
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: widget!,
    ),
    home: Scaffold(body: child),
  ),
);

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('RENDER_UI')) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.local/visual-review');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
