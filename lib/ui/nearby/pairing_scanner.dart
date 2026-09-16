import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

Future<String?> scanNearbyInvitation(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const _PairingScanner()));

class _PairingScanner extends StatefulWidget {
  const _PairingScanner();
  @override
  State<_PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<_PairingScanner> {
  bool _accepted = false;
  String? _message;

  void _detected(BarcodeCapture capture) {
    if (!mounted || _accepted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      try {
        PairingInvitation.decodeQr(value);
        _accepted = true;
        Navigator.pop(context, value);
        return;
      } catch (_) {
        if (_message == null) {
          setState(
            () => _message =
                'Scan the pairing code in MeowWatch on your desktop.',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair your desktop')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'On your desktop, open Nearby MeowWatch → Pair a phone. Keep the code inside the camera view.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: MobileScanner(
              // The widget owns the camera and handles lifecycle stop/resume/dispose.
              onDetect: _detected,
              onDetectError: (_, _) {
                if (mounted) {
                  setState(
                    () => _message =
                        'Could not read that code. Try again or paste the invitation.',
                  );
                }
              },
              errorBuilder: (context, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined, size: 42),
                      const SizedBox(height: 16),
                      const Text(
                        'Camera unavailable. Allow camera access in Android settings, or paste the pairing invitation instead.',
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
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_message!, textAlign: TextAlign.center),
            ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'The code stays on your devices. Confirm the pairing on your desktop.',
            ),
          ),
        ],
      ),
    ),
  );
}
