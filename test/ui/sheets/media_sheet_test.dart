import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/media/sample_video.dart';
import 'package:meowwatch_mobile/ui/media/media_sheet.dart';

import 'sheet_test_support.dart';

void main() {
  testWidgets(
    'returns a validated direct URL only after the picker exits',
    (tester) async {
      final app = createTestApp(billing: TestBilling());
      MediaItem? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showMediaSheet(context, app: app);
                  returned = true;
                  expect(
                    find.byType(TextField, skipOffstage: false),
                    findsNothing,
                  );
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
      final sheetRoute = ModalRoute.of(tester.element(find.byType(TextField)))!;
      await tester.ensureVisible(find.text('Use this link'));
      await tester.tap(find.text('Use this link'));
      await tester.pump();
      expect(sheetRoute.animation!.status, AnimationStatus.reverse);
      expect(find.byType(TextField), findsOneWidget);
      expect(returned, isFalse);
      expect(result, isNull);
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(result?.uri, Uri.parse('https://cdn.example.com/movie.mp4'));
      expect(app.target.snapshot.media, isNull);
      expect(tester.takeException(), isNull);
      await app.close();
    },
    semanticsEnabled: true,
  );

  testWidgets(
    'cancelling the picker returns no selection after its sheet exits',
    (tester) async {
      final app = createTestApp(billing: TestBilling());
      MediaItem? result = sampleVideo();
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showMediaSheet(context, app: app);
                  returned = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheetRoute = ModalRoute.of(tester.element(find.byType(TextField)))!;
      final navigator = sheetRoute.navigator!;
      navigator.pop();
      await tester.pump();
      expect(sheetRoute.animation!.status, AnimationStatus.reverse);
      expect(returned, isFalse);
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      expect(app.target.snapshot.media, isNull);
      expect(find.text('Open'), findsOneWidget);
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await app.close();
    },
    semanticsEnabled: true,
  );

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
    await tester.ensureVisible(find.text('Use this link'));
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

  testWidgets(
    'sample is an explicit one-tap media choice with source credits',
    (tester) async {
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
      expect(result, isNull);
      expect(app.target.snapshot.media, isNull);
      await tester.ensureVisible(find.text('Sample film credits'));
      await tester.tap(find.text('Sample film credits'));
      await tester.pumpAndSettle();
      expect(find.textContaining(sampleVideoCredit), findsOneWidget);
      expect(find.textContaining(sampleVideoLicenseUrl), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-sample-video')));
      await tester.tap(find.byKey(const Key('open-sample-video')));
      await tester.pumpAndSettle();
      expect(result?.uri, Uri.parse(sampleVideoUrl));
      expect(result?.title, sampleVideoTitle);
      expect(app.target.snapshot.media, isNull);
      await app.close();
    },
  );

  testWidgets(
    'source labels describe the real host without implying webpage playback',
    (tester) async {
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
      await tester.enterText(find.byType(TextField), sampleVideoUrl);
      await tester.pump();
      expect(find.text('Blender Open Movies · direct media'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://download.blender.org.evil.example/movie.mp4',
      );
      await tester.pump();
      expect(find.text('Blender Open Movies · direct media'), findsNothing);
      expect(find.text('download.blender.org.evil.example'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://archive.org/details/movie',
      );
      await tester.pump();
      expect(find.text('Internet Archive · direct media'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        'https://archive.org/download/movie/file.mp4',
      );
      await tester.pump();
      expect(find.text('Internet Archive · direct media'), findsOneWidget);
      expect(app.target.snapshot.media, isNull);
      await app.close();
    },
  );
}
