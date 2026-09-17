import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/platform/immersive_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.meowwatch.mobile/fullscreen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'room exit follows an in-flight entry before a replacement enters',
    () async {
      final entry = Completer<void>();
      final started = Completer<void>();
      final calls = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setEnabled');
        calls.add(call.arguments as bool);
        if (calls.length == 1) {
          started.complete();
          await entry.future;
        }
        return null;
      });

      final first = ImmersiveMode.setEnabled(true);
      await started.future;
      final exit = ImmersiveMode.setEnabled(false);
      final replacement = ImmersiveMode.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, [true]);
      entry.complete();
      await Future.wait([first, exit, replacement]);
      expect(calls, [true, false, true]);
      await ImmersiveMode.setEnabled(false);
    },
  );

  test(
    'failed entry is reported and does not block restoring the window',
    () async {
      final calls = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final enabled = call.arguments as bool;
        calls.add(enabled);
        if (enabled) throw PlatformException(code: 'fullscreen_unavailable');
        return null;
      });
      final entry = ImmersiveMode.setEnabled(true);
      final exit = ImmersiveMode.setEnabled(false);
      await expectLater(entry, throwsA(isA<PlatformException>()));
      await exit;
      expect(calls, [true, false]);
    },
  );
}
