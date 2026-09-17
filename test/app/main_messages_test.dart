import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/main.dart';

import '../support/sync_playback_fakes.dart';
import '../ui/sheets/sheet_test_support.dart';

void main() {
  testWidgets('successful media recovery removes the error and exposes Play', (
    tester,
  ) async {
    final target = _FailOnceTarget();
    final app = await _mount(tester, phone: target);

    await app.load(MediaItem.fromUrl('https://example.com/missing.mp4'));
    await _settleNotices(tester);
    expect(app.message, _FailOnceTarget.failure);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Dismiss'), findsOneWidget);

    await app.load(MediaItem.fromUrl('https://example.com/recovered.mp4'));
    await _settleNotices(tester);
    expect(app.message, isNull);
    expect(find.byType(SnackBar), findsNothing);
    final play = find.byTooltip('Play').hitTestable();
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.pump();
    expect(target.snapshot.playing, isTrue);
    expect(tester.takeException(), isNull);
    await _dispose(tester, app);
  });

  testWidgets(
    'replaced error retires and its old Dismiss cannot clear the new one',
    (tester) async {
      final app = await _mount(tester);
      app.report('First video failed.');
      await _settleNotices(tester);
      final oldDismiss = tester
          .widget<SnackBarAction>(find.byType(SnackBarAction))
          .onPressed;

      app.report('The replacement needs another link.');
      // A callback already captured from the previous frame must not dismiss the
      // new model message, even before the next frame replaces the notification.
      oldDismiss();
      expect(app.message, 'The replacement needs another link.');
      await _settleNotices(tester);
      expect(find.text('First video failed.'), findsNothing);
      expect(find.text('The replacement needs another link.'), findsOneWidget);
      oldDismiss();
      expect(app.message, 'The replacement needs another link.');

      await tester.tap(find.widgetWithText(SnackBarAction, 'Dismiss'));
      await _settleNotices(tester);
      expect(app.message, isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester, app);
    },
  );

  testWidgets(
    'clearing and reporting the same text makes the old Dismiss stale',
    (tester) async {
      final app = await _mount(tester);
      app.report('Choose another video.');
      await _settleNotices(tester);
      final oldDismiss = tester
          .widget<SnackBarAction>(find.byType(SnackBarAction))
          .onPressed;

      app.dismissMessage();
      app.report('Choose another video.');
      oldDismiss();
      expect(app.message, 'Choose another video.');
      await _settleNotices(tester);
      expect(find.text('Choose another video.'), findsOneWidget);
      oldDismiss();
      expect(app.message, 'Choose another video.');
      expect(tester.takeException(), isNull);
      await _dispose(tester, app);
    },
  );

  testWidgets(
    'retired queued errors leave surrounding unrelated notices intact',
    (tester) async {
      final app = await _mount(tester);
      final messenger = ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      );
      final incoming = messenger.showSnackBar(
        const SnackBar(
          content: Text('Incoming video needs review.'),
          duration: Duration(minutes: 1),
        ),
      );
      await _settleNotices(tester);

      app.report('Queued first error.');
      await _settleNotices(tester);
      app.report('Queued replacement error.');
      await _settleNotices(tester);
      app.dismissMessage();
      await _settleNotices(tester);
      expect(find.text('Incoming video needs review.'), findsOneWidget);
      expect(find.text('Queued first error.'), findsNothing);
      expect(find.text('Queued replacement error.'), findsNothing);

      var unrelatedClosed = false;
      final unrelated = messenger.showSnackBar(
        const SnackBar(
          content: Text('Room invitation copied.'),
          duration: Duration(minutes: 1),
        ),
      );
      unrelated.closed.then((_) => unrelatedClosed = true);
      incoming.close();
      await _settleNotices(tester);
      // onVisible schedules each retired notice's close in the next event turn.
      // pumpAndSettle waits for animation frames, not newly queued Timer.run
      // callbacks. Advance that event and its animation for both queued errors.
      for (var retiredNotice = 0; retiredNotice < 2; retiredNotice++) {
        await tester.pump();
        await tester.pumpAndSettle();
      }

      expect(find.text('Incoming video needs review.'), findsNothing);
      expect(find.text('Queued first error.'), findsNothing);
      expect(find.text('Queued replacement error.'), findsNothing);
      expect(find.text('Room invitation copied.'), findsOneWidget);
      expect(unrelatedClosed, isFalse);
      expect(tester.takeException(), isNull);
      await _dispose(tester, app);
    },
  );

  testWidgets('a same-frame external removal cannot close the next notice', (
    tester,
  ) async {
    final app = await _mount(tester);
    app.report('Old playback error.');
    await _settleNotices(tester);
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('An unrelated incoming notice.'),
        duration: Duration(minutes: 1),
      ),
    );
    // The framework removes the first queue entry synchronously, but its
    // controller.closed callback cannot run until these frame callbacks return.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger.removeCurrentSnackBar();
    });
    app.dismissMessage();
    await _settleNotices(tester);

    expect(find.text('Old playback error.'), findsNothing);
    expect(find.text('An unrelated incoming notice.'), findsOneWidget);
    expect(app.message, isNull);
    expect(tester.takeException(), isNull);
    await _dispose(tester, app);
  });
}

Future<AppController> _mount(
  WidgetTester tester, {
  SyncTestTarget? phone,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final app = AppController(
    repository: TestRepository(),
    billing: TestBilling(),
    hosting: TestQuota(),
    phone: phone ?? SyncTestTarget(),
    endpointSettings: TestEndpointSettings(),
  );
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MainApp(controller: app));
  await _settleNotices(tester);
  return app;
}

Future<void> _dispose(WidgetTester tester, AppController app) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await app.close();
}

Future<void> _settleNotices(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

class _FailOnceTarget extends SyncTestTarget {
  static const failure =
      'Could not load the video. Choose another file or link.';
  bool _shouldFail = true;

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    if (_shouldFail) {
      _shouldFail = false;
      emit(
        PlaybackSnapshot(
          media: media,
          connection: PlaybackConnection.failed,
          error: failure,
        ),
      );
      throw StateError('test decoder could not open the video');
    }
    await super.load(media, position: position);
  }
}
