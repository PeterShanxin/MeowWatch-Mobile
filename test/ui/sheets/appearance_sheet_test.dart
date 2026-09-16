import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/settings/appearance_sheet.dart';
import 'package:meowwatch_mobile/ui/settings/settings_sheet.dart';

import 'sheet_test_support.dart';

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
  test('Cozy remains the original default and unknown saved IDs fall back', () {
    final original = meowWatchTheme();
    expect(original.colorScheme.primary, const Color(0xFFEFB38C));
    expect(original.colorScheme.secondary, const Color(0xFFB9A9D3));
    expect(original.colorScheme.surface, const Color(0xFF10141F));
    expect(original.colorScheme.onSurface, const Color(0xFFF5EDE0));
    expect(original.colorScheme.surfaceContainer, const Color(0xFF1A2232));
    expect(
      original.colorScheme.surfaceContainerHighest,
      const Color(0xFF263045),
    );
    expect(original.textTheme.displayLarge?.fontFamily, 'DMSerifDisplay');
    expect(original.textTheme.displayLarge?.fontSize, 58);
    expect(meowWatchTheme(theme: 'removed-theme'), original);
    expect(meowWatchTheme(theme: 'cozy'), original);
  });

  test('all palettes keep readable text and filled controls', () {
    final backgrounds = <Color>{};
    for (final id in meowWatchThemeIds) {
      final scheme = meowWatchTheme(theme: id).colorScheme;
      backgrounds.add(scheme.surface);
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerHighest,
      ]) {
        expect(
          _contrast(scheme.onSurface, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$id primary text',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$id secondary text',
        );
      }
      expect(
        _contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.secondary, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(backgrounds, hasLength(3));
  });

  for (final id in ['cinemaNoir', 'glassAurora']) {
    testWidgets('settings routes locked $id to upgrade exactly once', (
      tester,
    ) async {
      final app = createTestApp(billing: TestBilling());
      var upgrades = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: meowWatchTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSettingsSheet(
                  context,
                  app: app,
                  onUpgrade: () {
                    upgrades++;
                    showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(title: Text('Upgrade destination')),
                    );
                  },
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      final appearance = find.byKey(const Key('choose-appearance-button'));
      await tester.ensureVisible(appearance);
      await tester.tap(appearance);
      await tester.pumpAndSettle();
      final choice = find.byKey(Key('theme-choice-$id'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(upgrades, 1);
      expect(find.text('Upgrade destination'), findsOneWidget);
      expect(find.byType(AppearanceSheet), findsNothing);
      expect(find.text('Settings'), findsNothing);
      expect(app.repository.theme, 'cozy');
      expect(app.needsPlus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await app.close();
    });

    testWidgets('free $id selection opens upgrade without persisting', (
      tester,
    ) async {
      final selected = <String>[];
      var upgrades = 0;
      await _open(
        tester,
        onSelect: (value) async => selected.add(value),
        onUpgrade: () => upgrades++,
      );
      expect(find.text('Plus'), findsNWidgets(2));
      final choice = find.byKey(Key('theme-choice-$id'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(upgrades, 1);
      expect(selected, isEmpty);
      expect(find.byType(AppearanceSheet), findsNothing);
    });
  }

  testWidgets('Plus applies only after save and ignores overlapping choices', (
    tester,
  ) async {
    final save = Completer<void>();
    final selected = <String>[];
    await _open(
      tester,
      isPlus: true,
      onSelect: (id) {
        selected.add(id);
        return save.future;
      },
    );
    final noir = find.byKey(const Key('theme-choice-cinemaNoir'));
    await tester.ensureVisible(noir);
    await tester.tap(noir);
    await tester.pump();
    expect(find.text('Cinema Noir applied.'), findsNothing);
    final aurora = find.byKey(const Key('theme-choice-glassAurora'));
    await tester.ensureVisible(aurora);
    await tester.tap(aurora);
    await tester.pump();
    expect(selected, ['cinemaNoir']);
    save.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cinema Noir applied.'), findsOneWidget);
  });

  testWidgets('failed save stays retryable and selecting Cozy is free', (
    tester,
  ) async {
    var attempts = 0;
    await _open(
      tester,
      currentTheme: 'cinemaNoir',
      onSelect: (id) async {
        expect(id, 'cozy');
        if (++attempts == 1) throw StateError('Storage unavailable');
      },
    );
    final cozy = find.byKey(const Key('theme-choice-cozy'));
    await tester.tap(cozy);
    await tester.pumpAndSettle();
    expect(find.text('Could not save your theme. Try again.'), findsOneWidget);
    expect(find.text('Cozy applied.'), findsNothing);
    await tester.tap(cozy);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Cozy applied.'), findsOneWidget);
  });

  for (final layout in [
    (name: 'phone', size: const Size(412, 892), scale: 1.0),
    (name: 'compact-2x', size: const Size(320, 568), scale: 2.0),
  ]) {
    testWidgets('${layout.name} reaches every actual themed preview', (
      tester,
    ) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await _open(
        tester,
        capture: capture,
        textScale: layout.scale,
        onSelect: (_) async {},
      );
      await _save(tester, capture, 'appearance-${layout.name}-overview');
      for (final id in meowWatchThemeIds) {
        final preview = find.byKey(Key('theme-preview-$id'));
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        expect(preview.hitTestable(), findsOneWidget);
        final decoration =
            tester.widget<DecoratedBox>(preview).decoration as BoxDecoration;
        expect(decoration.color, meowWatchTheme(theme: id).colorScheme.surface);
        expect(tester.takeException(), isNull);
        await _save(tester, capture, 'appearance-${layout.name}-$id');
      }
    });
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

Future<void> _open(
  WidgetTester tester, {
  String currentTheme = 'cozy',
  bool isPlus = false,
  double textScale = 1,
  required Future<void> Function(String) onSelect,
  VoidCallback? onUpgrade,
  GlobalKey? capture,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meowWatchTheme(theme: currentTheme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppearanceSheet(
                context,
                currentTheme: currentTheme,
                isPlus: isPlus,
                onSelect: onSelect,
                onUpgrade: onUpgrade ?? () {},
              ),
              child: const Text('Open appearance'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open appearance'));
  await tester.pumpAndSettle();
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
