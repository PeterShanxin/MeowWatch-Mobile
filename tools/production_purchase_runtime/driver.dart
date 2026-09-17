import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final runId = Platform.environment['BILLING_RUNTIME_RUN_ID'];
  if (runId != null && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(runId)) {
    throw ArgumentError('Invalid BILLING_RUNTIME_RUN_ID');
  }
  final output = Directory(
    'build/production-purchase-artifacts${runId == null ? '' : '/$runId'}',
  );
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
        throw ArgumentError('Invalid hosting screenshot name');
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      return bytes.length > 4096 &&
          List.generate(
            signature.length,
            (index) => index,
          ).every((index) => bytes[index] == signature[index]);
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File('${output.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
        flush: true,
      );
    },
  );
}
