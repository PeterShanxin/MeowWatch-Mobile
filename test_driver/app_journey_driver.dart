import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _profiles = {'phone', 'small', 'tablet', 'tablet-landscape', 'landscape'};
const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Future<void> main() async {
  final profile = Platform.environment['UI_PROFILE'];
  if (!_profiles.contains(profile)) {
    throw ArgumentError('UI_PROFILE must be one of ${_profiles.join(', ')}.');
  }

  final root = Directory('build/app-journey-artifacts/$profile');
  final screenshotsDirectory = Directory('${root.path}/screenshots');
  if (await screenshotsDirectory.exists()) {
    await screenshotsDirectory.delete(recursive: true);
  }
  await screenshotsDirectory.create(recursive: true);
  final screenshots = <String>[];

  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
        throw ArgumentError('Unsafe screenshot name: $name');
      }
      final validPng =
          bytes.length > 4096 &&
          bytes.length >= _pngSignature.length &&
          Iterable<int>.generate(
            _pngSignature.length,
          ).every((index) => bytes[index] == _pngSignature[index]);
      if (!validPng) return false;
      await File(
        '${screenshotsDirectory.path}${Platform.pathSeparator}$name.png',
      ).writeAsBytes(bytes, flush: true);
      screenshots.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final summary = Map<String, dynamic>.from(data ?? <String, dynamic>{})
        ..remove('screenshots');
      summary['driver'] = <String, Object>{
        'uiProfile': profile!,
        'artifactDirectory': root.path,
        'screenshots': screenshots,
        'screenshotCount': screenshots.length,
        'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
      };
      await root.create(recursive: true);
      await File(
        '${root.path}${Platform.pathSeparator}result.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
        flush: true,
      );
      final journey = summary['appJourney'];
      if (journey is Map && journey['result'] == 'passed') {
        final viewport = journey['viewport'];
        final expectedOrientation =
            profile == 'landscape' || profile == 'tablet-landscape'
            ? 'landscape'
            : 'portrait';
        if (viewport is! Map ||
            viewport['orientation'] != expectedOrientation) {
          throw StateError(
            'Native viewport did not match $profile orientation.',
          );
        }
      }
    },
  );
}
