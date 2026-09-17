import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Keeps Android's ordinary rendering surface active between screenshots.
///
/// Create one instance inside each testWidgets body. This uses Flutter 3.44.0's
/// integration_test channel protocol; see README.md before upgrading Flutter.
final class NativeScreenshots {
  NativeScreenshots(this._binding) : _isAndroid = Platform.isAndroid;

  @visibleForTesting
  NativeScreenshots.forPlatform(this._binding, {required this._isAndroid});

  static const _channel = MethodChannel('plugins.flutter.io/integration_test');
  final IntegrationTestWidgetsFlutterBinding _binding;
  final bool _isAndroid;
  bool _registered = false;
  bool _capturing = false;

  Future<List<int>> take(WidgetTester tester, String name) async {
    if (_capturing) {
      throw StateError('Native screenshot captures must not overlap.');
    }
    _capturing = true;
    try {
      if (!_isAndroid) {
        tester.binding.scheduleFrame();
        await tester.pump();
        return await _binding.takeScreenshot(name);
      }
      try {
        if (!_registered) {
          // Registers the SDK's Dart screenshot state and exactly one teardown.
          await _binding.convertFlutterSurfaceToImage();
          _registered = true;
        } else {
          // The SDK's Dart state stays registered until its test teardown, but
          // the native surface is reverted after every capture below.
          await _channel.invokeMethod<void>('convertFlutterSurfaceToImage');
        }
        // A surface swap does not dirty a widget. Automated bindings only draw
        // on pump when a frame was scheduled, so request one explicitly.
        tester.binding.scheduleFrame();
        await tester.pump();
        // Preserve the SDK reportData and integrationDriver screenshot callback.
        return await _binding.takeScreenshot(name);
      } finally {
        await _channel.invokeMethod<void>('revertFlutterImage');
        // The native channel acknowledges before FlutterView's first-frame
        // callback. Render on the resumed surface and allow that callback time.
        // This is settling, not a native completion acknowledgement.
        tester.binding.scheduleFrame();
        await tester.pump();
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 100));
      }
    } finally {
      _capturing = false;
    }
  }
}
