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
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^network-[A-Za-z0-9_-]+$').hasMatch(name)) {
        throw ArgumentError('Invalid network screenshot name');
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
