import 'dart:io';
import 'dart:ui' as ui;

import 'package:meowwatch_mobile/ui/shared/invitation_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Decodes a real generated invitation with Android's native ML Kit plugin.
/// This is image-analysis evidence, not a camera/permission or optical scan test.
/// Call while no camera scanner route is open.
Future<String> decodeGeneratedInviteQr(String actualInviteUrl) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('Native invite QR acceptance requires Android.');
  }
  if (validateScannedInvitation(actualInviteUrl, InvitationScanPurpose.room) !=
      actualInviteUrl) {
    throw ArgumentError('The generated invitation must be canonical.');
  }

  final directory = await Directory.systemTemp.createTemp(
    'meowwatch-invite-qr-',
  );
  final file = File('${directory.path}/invite.png');
  final scanner = MobileScannerController(autoStart: false);
  try {
    const pixels = 640;
    const margin = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 640, 640),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.translate(margin, margin);
    QrPainter(
      data: actualInviteUrl,
      version: QrVersions.auto,
      gapless: true,
    ).paint(canvas, const ui.Size(pixels - 2 * margin, pixels - 2 * margin));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(pixels, pixels);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null || png.lengthInBytes == 0) {
          throw StateError('Could not rasterize the room invitation QR.');
        }
        await file.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          flush: true,
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }

    final capture = await scanner
        .analyzeImage(file.path, formats: const [BarcodeFormat.qrCode])
        .timeout(const Duration(seconds: 30));
    final codes = capture?.barcodes
        .where((code) => code.format == BarcodeFormat.qrCode)
        .toList(growable: false);
    if (codes == null ||
        codes.length != 1 ||
        codes.single.rawValue != actualInviteUrl) {
      throw StateError(
        'Native QR decoding did not return the exact invitation.',
      );
    }
    return validateScannedInvitation(
      codes.single.rawValue!,
      InvitationScanPurpose.room,
    );
  } finally {
    try {
      // autoStart:false never attaches a camera or creates stream listeners.
      await scanner.dispose().timeout(const Duration(seconds: 10));
    } finally {
      if (await file.exists()) await file.delete();
      await directory.delete();
    }
  }
}
