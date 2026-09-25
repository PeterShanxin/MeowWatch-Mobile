import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Future<void> main() async {
  final role = Platform.environment['TOGETHER_ROLE'];
  if (!['host', 'guest'].contains(role)) {
    throw ArgumentError('TOGETHER_ROLE must be host or guest.');
  }

  final root = Directory('build/production-together-artifacts/$role');
  final screenshotsDirectory = Directory('${root.path}/screenshots');
  if (await screenshotsDirectory.exists()) {
    await screenshotsDirectory.delete(recursive: true);
  }
  await screenshotsDirectory.create(recursive: true);
  final screenshots = <String>[];

  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^(host|guest)-[a-z0-9-]+$').hasMatch(name)) {
        throw ArgumentError(
          'Unsafe production-together screenshot name: $name',
        );
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
      final journey = summary['productionTogether'];
      if (journey is! Map ||
          journey['result'] != 'passed' ||
          journey['role'] != role) {
        throw StateError(
          'Production together result did not pass for driver role $role.',
        );
      }
      summary['driver'] = <String, Object>{
        'role': role!,
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
    },
  );
}
