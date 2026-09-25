import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/devices/playback_devices_sheet.dart';

import '../home/ui_test_support.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'DMSans': 'assets/fonts/DMSans.ttf',
      'DMSerifDisplay': 'assets/fonts/DMSerifDisplay.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final url in <String?>[
    null,
    'https://example.com/video.mp4?token=private',
    'https://example.com/video.mp4',
  ]) {
    testWidgets('screen choice explains Cast availability for $url', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = UiTestApp.create();
      PlaybackDeviceChoice? choice;
      try {
        await fixture.controller.useLocalMode();
        if (url != null) await fixture.controller.load(MediaItem.fromUrl(url));
        await tester.pumpWidget(
          MaterialApp(
            theme: meowWatchTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      choice = await showPlaybackDevicesSheet(
                        context,
                        app: fixture.controller,
                      );
                    },
                    child: const Text('Choose screen'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose screen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final castTile = tester.widget<ListTile>(
          find.descendant(
            of: find.byKey(const Key('playback-device-cast')),
            matching: find.byType(ListTile),
          ),
        );
        expect(castTile.enabled, url == 'https://example.com/video.mp4');
        if (url == null) {
          expect(
            find.text('Open a public HTTPS MP4 video on this phone first.'),
            findsOneWidget,
          );
        } else if (url.contains('?')) {
          expect(
            find.textContaining('without sign-in or URL parameters'),
            findsOneWidget,
          );
        } else {
          await tester.ensureVisible(find.text('Google Cast'));
          await tester.tap(find.text('Google Cast'));
          await tester.pumpAndSettle();
          expect(choice, PlaybackDeviceChoice.cast);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.close);
      }
    });
  }
  for (final view in {
    'small-phone': const Size(360, 640),
    'tablet': const Size(1280, 800),
    'landscape-phone': const Size(800, 360),
  }.entries) {
    testWidgets('${view.key} screen picker remains usable at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = view.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = UiTestApp.create();
      final capture = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: meowWatchTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showPlaybackDevicesSheet(
                      context,
                      app: fixture.controller,
                    ),
                    child: const Text('Choose screen'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose screen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('RENDER_UI')) {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.local/visual-review/${view.key}-screen-picker.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.text('Google Cast'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Google Cast').hitTestable(), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.close);
      }
    });
  }
}
