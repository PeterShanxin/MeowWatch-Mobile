import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/ui/media/media_sheet.dart';

import 'sheet_test_support.dart';

void main() {
  testWidgets('returns a validated direct URL without loading it', (
    tester,
  ) async {
    final app = createTestApp(billing: TestBilling());
    MediaItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showMediaSheet(context, app: app);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://cdn.example.com/movie.mp4',
    );
    await tester.tap(find.text('Use this link'));
    await tester.pumpAndSettle();

    expect(result?.uri, Uri.parse('https://cdn.example.com/movie.mp4'));
    expect(app.target.snapshot.media, isNull);
    await app.close();
  });

  testWidgets('rejects webpage URLs and clears the error while editing', (
    tester,
  ) async {
    final app = createTestApp(billing: TestBilling());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMediaSheet(context, app: app),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://youtube.com/watch');
    await tester.tap(find.text('Use this link'));
    await tester.pump();
    expect(find.textContaining('This is a webpage'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://cdn.example.com/movie.mp4',
    );
    await tester.pump();
    expect(find.textContaining('This is a webpage'), findsNothing);
    await app.close();
  });

  testWidgets('remains scrollable on a small phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = createTestApp(billing: TestBilling());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMediaSheet(context, app: app),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('DRM-protected'));
    await tester.pump();
    expect(find.textContaining('DRM-protected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.close();
  });
}
