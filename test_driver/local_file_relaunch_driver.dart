import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Future<void> main() async {
  final stageText = Platform.environment['LOCAL_FILE_RUNTIME_STAGE'];
  final stage = int.tryParse(stageText ?? '');
  if (stage == null || stage < 1 || stage > 2) {
    throw ArgumentError('LOCAL_FILE_RUNTIME_STAGE must be 1 or 2.');
  }
  final root = Directory('build/local-file-runtime-artifacts/stage-$stage');
  final screenshots = Directory('${root.path}/screenshots');
  await screenshots.create(recursive: true);
  final screenshotNames = <String>[];

  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^local-file-[a-z-]+$').hasMatch(name)) return false;
      final valid =
          bytes.length > 4096 &&
          bytes.length >= _pngSignature.length &&
          Iterable<int>.generate(
            _pngSignature.length,
          ).every((index) => bytes[index] == _pngSignature[index]);
      if (!valid) return false;
      await File(
        '${screenshots.path}${Platform.pathSeparator}$name.png',
      ).writeAsBytes(bytes, flush: true);
      screenshotNames.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? <String, dynamic>{})
        ..remove('screenshots');
      final runtime = report['localFileRuntime'];
      if (runtime is! Map ||
          runtime['stage'] != stage ||
          runtime['completed'] != true) {
        throw StateError('Device reported an unexpected local-file stage.');
      }
      report['driver'] = <String, Object?>{
        'stage': stage,
        'screenshots': screenshotNames,
      };
      await root.create(recursive: true);
      await File('${root.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    },
  );
}
