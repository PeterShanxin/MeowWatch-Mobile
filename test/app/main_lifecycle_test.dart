import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/main.dart';

import '../ui/sheets/sheet_test_support.dart';

void main() {
  for (final configured in [false, true]) {
    testWidgets(
      'HOME pause requires visible Play with billing configured=$configured',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final billing = TestBilling();
        if (configured) await billing.configure();
        final app = createTestApp(billing: billing);
        await app.load(MediaItem.fromUrl('https://example.com/movie.mp4'));
        await app.togglePlay();
        await tester.pumpWidget(MainApp(controller: app));
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(app.phone.snapshot.playing, isFalse);
        await app.togglePlay();
        expect(app.phone.snapshot.playing, isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(app.phone.snapshot.playing, isFalse);
        expect(billing.refreshCalls, configured ? 1 : 0);
        await app.togglePlay();
        expect(app.phone.snapshot.playing, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      },
    );
  }
}
