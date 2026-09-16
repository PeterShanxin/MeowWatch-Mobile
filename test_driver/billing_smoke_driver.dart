import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final runId = Platform.environment['BILLING_RUNTIME_RUN_ID'];
  if (runId != null && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(runId)) {
    throw ArgumentError('Invalid BILLING_RUNTIME_RUN_ID');
  }
  final output = Directory(
    'build/billing-runtime-artifacts${runId == null ? '' : '/$runId'}',
  );
  await output.create(recursive: true);
  await integrationDriver(
    timeout: const Duration(minutes: 10),
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      await File('${output.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
    },
  );
}
