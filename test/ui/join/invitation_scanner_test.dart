import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/nearby/pairing_scanner.dart';
import 'package:meowwatch_mobile/ui/shared/invitation_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import 'scanner_test_support.dart';

const _invite =
    'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8999';

void main() {
  test('room scanner keeps endpoint and rejects foreign or malformed QR', () {
    expect(
      validateScannedInvitation(_invite, InvitationScanPurpose.room),
      _invite,
    );
    for (final value in [
      'quiet-otter',
      'https://example.org/',
      'meowwatch://join?room=movie&server=syncplay.pl&port=0',
      'meowwatch://join?room=movie&server=bad%2Fhost&port=8995',
    ]) {
      expect(
        () => validateScannedInvitation(value, InvitationScanPurpose.room),
        throwsFormatException,
      );
    }
  });

  test('nearby and room invitations are purpose-specific', () {
    final pairing = PairingInvitation(
      desktopId: encodeBytes(List<int>.filled(16, 10)),
      pairId: encodeBytes(List<int>.filled(16, 11)),
      endpoint: LanEndpoint(
        address: LanIpv4Address.parse('192.168.1.30'),
        port: 9443,
      ),
      certificateSha256: List<int>.filled(32, 12),
      pairSecret: List<int>.filled(16, 13),
    ).encodeQr();
    expect(
      validateScannedInvitation(pairing, InvitationScanPurpose.nearby),
      pairing,
    );
    expect(
      () => validateScannedInvitation(pairing, InvitationScanPurpose.room),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Use Nearby MeowWatch'),
        ),
      ),
    );
    expect(
      () => validateScannedInvitation(_invite, InvitationScanPurpose.nearby),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Use Join a room'),
        ),
      ),
    );
  });

  late MobileScannerPlatform previous;
  late TestScannerPlatform scanner;
  setUp(() {
    previous = MobileScannerPlatform.instance;
    scanner = TestScannerPlatform();
    MobileScannerPlatform.instance = scanner;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = previous;
    await scanner.captures.close();
  });

  testWidgets('wrong nearby purpose stays on scanner and Back cancels', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await scanNearbyInvitation(context),
              child: const Text('Scan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    scanner.emit(_invite);
    await tester.pumpAndSettle();
    expect(
      find.text('This joins a room. Use Join a room to scan it.'),
      findsOneWidget,
    );
    expect(result, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
    await expectScannerReleased(tester, scanner, 1);
  });

  testWidgets('camera denial offers cancellation on a small 200% screen', (
    tester,
  ) async {
    scanner.denyPermission = true;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowWatchTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => scanRoomInvitation(context),
              child: const Text('Scan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('paste the room invitation'), findsOneWidget);
    final fallback = find.text('Use an invitation instead');
    await tester.ensureVisible(fallback);
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(find.byType(InvitationScanner), findsNothing);
    await expectScannerReleased(tester, scanner, 1);
    expect(tester.takeException(), isNull);
  });
}
