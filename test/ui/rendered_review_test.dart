import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/main.dart';

import 'home/ui_test_support.dart';

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

  for (final size in <String, Size>{
    'small-phone': const Size(360, 640),
    'phone': const Size(412, 892),
    'tablet': const Size(1280, 800),
    'portrait-tablet': const Size(800, 1280),
    'landscape-phone': const Size(800, 360),
  }.entries) {
    testWidgets(
      '${size.key} first launch, home and local player render without overflow',
      (tester) async {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = UiTestApp.create();
        try {
          final capture = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MainApp(controller: fixture.controller),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _save(tester, capture, '${size.key}-onboarding');
          await fixture.controller.setName('Milo');
          await tester.pumpAndSettle();
          expect(find.text('Start a room'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _save(tester, capture, '${size.key}-home');
          await fixture.controller.useLocalMode();
          await tester.pumpAndSettle();
          expect(find.text('Choose a video'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _save(tester, capture, '${size.key}-player');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(fixture.close);
        }
      },
    );
  }
}

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
