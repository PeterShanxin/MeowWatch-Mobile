import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/settings/about_sheet.dart';

void main() {
  test('displayed version stays aligned with pubspec', () {
    final versionLine = File(
      'pubspec.yaml',
    ).readAsLinesSync().singleWhere((line) => line.startsWith('version:'));
    expect(meowWatchVersion, versionLine.split(':').last.trim());
  });

  test('bundled app and font license files exist', () {
    expect(
      bundledLicenseAssets.keys,
      containsAll(<String>[
        'LICENSE',
        'assets/fonts/DMSans-OFL.txt',
        'assets/fonts/DMSerifDisplay-OFL.txt',
      ]),
    );
    for (final path in bundledLicenseAssets.keys) {
      expect(File(path).lengthSync(), greaterThan(100));
    }
  });

  testWidgets('shows honest privacy, source and license entry points', (
    tester,
  ) async {
    var licenseCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AboutSheet(onShowLicenses: () => licenseCalls++)),
      ),
    );

    expect(find.text('About MeowWatch'), findsOneWidget);
    expect(find.text('Version $meowWatchVersion'), findsOneWidget);
    expect(find.text('AGPL-3.0-only'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Together Rooms'), findsOneWidget);
    expect(find.text('RevenueCat'), findsOneWidget);
    expect(find.text('Nearby MeowWatch'), findsOneWidget);
    expect(find.text(meowWatchSourceUrl), findsOneWidget);
    expect(find.text(meowWatchSyncCoreSourceUrl), findsOneWidget);

    final licenses = find.byKey(const Key('open-source-licenses-button'));
    await tester.ensureVisible(licenses);
    await tester.tap(licenses);
    await tester.pump();
    expect(licenseCalls, 1);
  });
}
