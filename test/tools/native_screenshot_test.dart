import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../tools/native_capture/native_screenshot.dart';

const _channel = MethodChannel('plugins.flutter.io/integration_test');

void main() {
  testWidgets('each capture restores rendering and registers SDK state once', (
    tester,
  ) async {
    final surface = _Surface(tester);
    surface.install();
    final binding = _ScreenshotBinding(surface);
    final screenshots = NativeScreenshots.forPlatform(binding, isAndroid: true);

    expect(await screenshots.take(tester, 'first'), [1, 2, 3]);
    expect(surface.converted, isFalse);
    expect(await screenshots.take(tester, 'second'), [1, 2, 3]);
    expect(surface.converted, isFalse);
    expect(binding.registrations, 1);
    expect(binding.names, ['first', 'second']);
    expect(surface.events, [
      'convert',
      'image frame',
      'capture first',
      'revert',
      'surface frame',
      'convert',
      'image frame',
      'capture second',
      'revert',
      'surface frame',
    ]);
  });

  testWidgets(
    'failed capture restores rendering and permits the next capture',
    (tester) async {
      final surface = _Surface(tester);
      surface.install();
      final binding = _ScreenshotBinding(surface)..failCapture = true;
      final screenshots = NativeScreenshots.forPlatform(
        binding,
        isAndroid: true,
      );

      await expectLater(
        screenshots.take(tester, 'failed'),
        throwsA(isA<PlatformException>()),
      );
      expect(surface.converted, isFalse);
      expect(surface.events.last, 'surface frame');
      binding.failCapture = false;
      expect(await screenshots.take(tester, 'retry'), [1, 2, 3]);
      expect(binding.registrations, 1);
      expect(surface.converted, isFalse);
    },
  );

  testWidgets('failed initial conversion also attempts native cleanup', (
    tester,
  ) async {
    final surface = _Surface(tester)..failConversion = true;
    surface.install();
    final binding = _ScreenshotBinding(surface);
    final screenshots = NativeScreenshots.forPlatform(binding, isAndroid: true);

    await expectLater(
      screenshots.take(tester, 'failed'),
      throwsA(isA<PlatformException>()),
    );
    expect(surface.converted, isFalse);
    expect(binding.names, isEmpty);
    expect(surface.events, ['convert', 'revert', 'surface frame']);
  });

  testWidgets('other platforms delegate without Android surface commands', (
    tester,
  ) async {
    final surface = _Surface(tester);
    surface.install();
    final binding = _ScreenshotBinding(surface)
      ..requireConvertedSurface = false;
    final screenshots = NativeScreenshots.forPlatform(
      binding,
      isAndroid: false,
    );

    expect(await screenshots.take(tester, 'desktop'), [1, 2, 3]);
    expect(binding.registrations, 0);
    expect(surface.events, ['capture desktop']);
  });
}

final class _Surface {
  _Surface(this.tester);

  final WidgetTester tester;
  final events = <String>[];
  bool converted = false;
  bool imageFrameReady = false;
  bool failConversion = false;

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      switch (call.method) {
        case 'convertFlutterSurfaceToImage':
          events.add('convert');
          expect(converted, isFalse);
          converted = true;
          imageFrameReady = false;
          if (failConversion) {
            throw PlatformException(code: 'conversion failed');
          }
          tester.binding.addPostFrameCallback((_) {
            events.add('image frame');
            imageFrameReady = true;
          });
        case 'revertFlutterImage':
          events.add('revert');
          converted = false;
          tester.binding.addPostFrameCallback((_) {
            events.add('surface frame');
          });
        default:
          throw StateError('Unexpected native call: ${call.method}');
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    });
  }
}

final class _ScreenshotBinding extends Fake
    implements IntegrationTestWidgetsFlutterBinding {
  _ScreenshotBinding(this.surface);

  final _Surface surface;
  final names = <String>[];
  int registrations = 0;
  bool failCapture = false;
  bool requireConvertedSurface = true;

  @override
  Future<void> convertFlutterSurfaceToImage() async {
    await _channel.invokeMethod<void>('convertFlutterSurfaceToImage');
    registrations++;
  }

  @override
  Future<List<int>> takeScreenshot(
    String screenshotName, [
    Map<String, Object?>? args,
  ]) async {
    if (requireConvertedSurface) {
      expect(surface.converted, isTrue);
      expect(surface.imageFrameReady, isTrue);
    }
    names.add(screenshotName);
    surface.events.add('capture $screenshotName');
    if (failCapture) {
      throw PlatformException(code: 'capture failed');
    }
    return [1, 2, 3];
  }
}
