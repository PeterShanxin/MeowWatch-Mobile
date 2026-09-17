import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Widget-only camera substitute. It does not establish native QR decoding.
class TestScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  bool denyPermission = false;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  void emit(String value) => captures.add(
    BarcodeCapture(
      barcodes: [Barcode(rawValue: value, format: BarcodeFormat.qrCode)],
    ),
  );

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denyPermission) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Widget buildCameraView() => const SizedBox.expand();
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async => disposals++;
}

Future<void> expectScannerReleased(
  WidgetTester tester,
  TestScannerPlatform scanner,
  int count,
) async {
  expect(find.byType(MobileScanner, skipOffstage: false), findsNothing);
  // MobileScanner disposes asynchronously after its route is removed. Its
  // stream cancellation may finish outside the widget test's fake clock.
  for (var turn = 0; scanner.disposals < count && turn < 20; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(
    scanner.disposals,
    count,
    reason:
        'The removed scanner must release its platform camera; '
        'starts=${scanner.starts}, stops=${scanner.stops}',
  );
  expect(scanner.captures.hasListener, isFalse);
}
