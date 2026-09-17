import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import '../../core/session/room_invite.dart';

enum InvitationScanPurpose { room, nearby }

String validateScannedInvitation(String raw, InvitationScanPurpose purpose) {
  final value = raw.trim();
  if (purpose == InvitationScanPurpose.room) {
    if (value.startsWith('meowwatch-pair:')) {
      throw const FormatException(
        'This pairs a desktop. Use Nearby MeowWatch to pair it.',
      );
    }
    final uri = Uri.tryParse(value);
    if (value.length > 512 ||
        uri?.scheme != 'meowwatch' ||
        uri?.host != 'join') {
      throw const FormatException('This is not a MeowWatch room invitation.');
    }
    parseRoomInvite(value, '');
  } else {
    if (Uri.tryParse(value)?.scheme == 'meowwatch') {
      throw const FormatException(
        'This joins a room. Use Join a room to scan it.',
      );
    }
    try {
      PairingInvitation.decodeQr(value);
    } catch (_) {
      throw const FormatException(
        'Scan the pairing code in MeowWatch on your desktop.',
      );
    }
  }
  return value;
}

Future<String?> scanRoomInvitation(BuildContext context) =>
    showInvitationScanner(context, InvitationScanPurpose.room);

Future<String?> showInvitationScanner(
  BuildContext context,
  InvitationScanPurpose purpose,
) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => InvitationScanner(purpose: purpose)),
  );
}

class InvitationScanner extends StatefulWidget {
  const InvitationScanner({super.key, required this.purpose});

  final InvitationScanPurpose purpose;

  @override
  State<InvitationScanner> createState() => _InvitationScannerState();
}

class _InvitationScannerState extends State<InvitationScanner> {
  bool _accepted = false;
  String? _message;

  bool get _room => widget.purpose == InvitationScanPurpose.room;

  void _detected(BarcodeCapture capture) {
    if (!mounted || _accepted) return;
    String? error;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || barcode.format != BarcodeFormat.qrCode) continue;
      try {
        final value = validateScannedInvitation(raw, widget.purpose);
        _accepted = true;
        Navigator.of(context).pop(value);
        return;
      } on FormatException catch (invalid) {
        error ??= invalid.message;
      }
    }
    if (error != null && error != _message) {
      setState(() => _message = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_room ? 'Scan a room invite' : 'Pair your desktop'),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _room
                          ? 'Ask your friend to open their room’s invite. Keep the QR code inside the camera view.'
                          : 'On your desktop, open Nearby MeowWatch → Pair a phone. Keep the code inside the camera view.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(
                    height: (constraints.maxHeight * 0.5).clamp(200, 420),
                    child: MobileScanner(
                      // No external controller: the widget owns camera
                      // lifecycle, stream cancellation and disposal.
                      onDetect: _detected,
                      onDetectError: (_, _) {
                        if (mounted && !_accepted) {
                          setState(
                            () => _message =
                                'Could not read that code. Try again or paste the invitation.',
                          );
                        }
                      },
                      errorBuilder: (context, _) => SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.no_photography_outlined, size: 42),
                            const SizedBox(height: 16),
                            Text(
                              _room
                                  ? 'Camera unavailable. Allow camera access in Android settings, or paste the room invitation instead.'
                                  : 'Camera unavailable. Allow camera access in Android settings, or paste the pairing invitation instead.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Use an invitation instead'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_message!, textAlign: TextAlign.center),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _room
                          ? 'Scanning does not join the room. Review the room and server before joining.'
                          : 'The code stays on your devices. Confirm the pairing on your desktop.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
