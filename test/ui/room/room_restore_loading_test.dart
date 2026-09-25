import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';

import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

class _DeferredLoadTarget extends SyncTestTarget {
  Completer<void>? beforeLoad;
  bool waitingBeforeLoad = false;

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final gate = beforeLoad;
    beforeLoad = null;
    if (gate != null) {
      waitingBeforeLoad = true;
      await gate.future;
      waitingBeforeLoad = false;
    }
    await super.load(media, position: position);
  }
}

void main() {
  testWidgets('history restore hides stale video and disables old controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    final target = _DeferredLoadTarget();
    final app = AppController(
      repository: UiTestRepository(),
      billing: UiTestBilling(),
      hosting: UiTestHosting(),
      phone: target,
      endpointSettings: MemoryEndpointSettings(),
    );
    final media = MediaItem.fromUrl('https://example.com/movie.mp4');
    final gate = Completer<void>();
    Future<void>? restoring;
    try {
      await app.useLocalMode();
      await app.load(media);
      await tester.pumpWidget(
        MaterialApp(
          home: RoomScreen(
            app: app,
            onLoad: () {},
            onInvite: () {},
            onDevices: () {},
            onLeave: () {},
            onStartRoom: () {},
            onTogglePlay: () => unawaited(app.togglePlay()),
            onSeek: (position) => unawaited(app.seek(position)),
          ),
        ),
      );
      target.beforeLoad = gate;
      restoring = app.resume(
        WatchHistoryEntry(
          media: media,
          position: const Duration(seconds: 24),
          duration: const Duration(minutes: 5),
          updatedAt: DateTime(2026, 9, 25),
        ),
      );
      for (var turn = 0; !target.waitingBeforeLoad && turn < 20; turn++) {
        await tester.pump();
      }
      expect(target.waitingBeforeLoad, isTrue);
      expect(target.snapshot.ready, isTrue);
      expect(target.snapshot.media?.uri, media.uri);
      expect(app.isRestoringHistory, isTrue);
      await tester.pump();

      final play = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Play',
      );
      expect((tester.widget<IconButton>(play)).onPressed, isNull);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      for (final tooltip in ['Back 10 seconds', 'Forward 10 seconds']) {
        final button = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        );
        expect(tester.widget<IconButton>(button).onPressed, isNull);
      }
      expect(find.text('Restoring your video…'), findsOneWidget);

      gate.complete();
      await restoring;
      await tester.pump();
      expect(app.isRestoringHistory, isFalse);
      expect((tester.widget<IconButton>(play)).onPressed, isNotNull);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(find.text('Restoring your video…'), findsNothing);
      await tester.tap(play);
      await tester.pump();
      expect(
        target.commands.where((command) => command == 'play'),
        hasLength(1),
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (restoring != null) await restoring;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(app.close);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
