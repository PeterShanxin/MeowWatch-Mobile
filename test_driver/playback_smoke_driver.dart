import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _artifactDirectory = 'build/android-runtime-artifacts';

Future<void> main() async {
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      final screenshots = Directory('$_artifactDirectory/screenshots');
      await screenshots.create(recursive: true);
      await File(
        '${screenshots.path}${Platform.pathSeparator}$name.png',
      ).writeAsBytes(bytes, flush: true);

      const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      final hasPngSignature =
          bytes.length >= pngSignature.length &&
          Iterable<int>.generate(
            pngSignature.length,
          ).every((index) => bytes[index] == pngSignature[index]);
      return hasPngSignature && bytes.length > 4096;
    },
    responseDataCallback: (data) async {
      final artifacts = Directory(_artifactDirectory);
      await artifacts.create(recursive: true);
      final summary = Map<String, dynamic>.from(data ?? <String, dynamic>{})
        ..remove('screenshots');
      await File(
        '${artifacts.path}${Platform.pathSeparator}result.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
        flush: true,
      );
    },
  );
}
