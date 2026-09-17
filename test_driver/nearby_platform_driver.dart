import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final stageText = Platform.environment['NEARBY_RUNTIME_STAGE'];
  final stage = int.tryParse(stageText ?? '');
  if (stage == null || stage < 1 || stage > 3) {
    throw ArgumentError('NEARBY_RUNTIME_STAGE must be 1, 2 or 3.');
  }
  final output = Directory('build/nearby-runtime-artifacts/stage-$stage');
  await output.create(recursive: true);
  await integrationDriver(
    timeout: const Duration(minutes: 4),
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? <String, dynamic>{});
      final nearby = report['nearbyRuntime'];
      if (nearby is! Map || nearby['stage'] != stage) {
        throw StateError('Device reported an unexpected Nearby runtime stage.');
      }
      await File('${output.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    },
  );
}
