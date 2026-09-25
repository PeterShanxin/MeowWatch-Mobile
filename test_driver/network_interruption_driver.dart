import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final runId = Platform.environment['NETWORK_RUN_ID'] ?? '';
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(runId)) {
    throw ArgumentError('A valid NETWORK_RUN_ID is required.');
  }
  final output = Directory('build/android-network-artifacts/$runId');
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {});
      await File('${output.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
        flush: true,
      );
    },
  );
}
