import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final role = Platform.environment['TOGETHER_ROLE'];
  if (!['host', 'guest'].contains(role)) {
    throw ArgumentError('TOGETHER_ROLE must be host or guest.');
  }
  final root = Directory('build/android-multi-device-artifacts/$role');
  await root.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      await File('${root.path}/$name.png').writeAsBytes(bytes, flush: true);
      return bytes.length > 4096;
    },
    responseDataCallback: (data) async {
      final summary = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File('${root.path}/result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
        flush: true,
      );
    },
  );
}
