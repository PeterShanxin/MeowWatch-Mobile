import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/native_focus_stage_client.dart';

void main() {
  test(
    'native stage sender uses bounded fixed-length JSON over HTTP',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received =
          Completer<
            ({String? length, String? encoding, String path, String body})
          >();
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (buffer, part) => buffer..addAll(part),
        );
        final length = request.headers.value(HttpHeaders.contentLengthHeader);
        final encoding = request.headers.value(
          HttpHeaders.transferEncodingHeader,
        );
        final body = utf8.decode(bytes);
        Object? payload;
        try {
          payload = jsonDecode(body);
        } on FormatException {
          payload = null;
        }
        final valid =
            length != null &&
            RegExp(r'^[0-9]+$').hasMatch(length) &&
            int.parse(length) <= 128 &&
            int.parse(length) == bytes.length &&
            encoding == null &&
            request.uri.path == '/permanent-acquire' &&
            payload is Map &&
            payload.length == 1 &&
            payload['stage'] == 'permanent-acquire';
        // Use the same strict framing boundary as the native stage server,
        // while retaining the raw request for the test's body assertion.
        request.response.statusCode = valid ? 200 : 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            valid
                ? {'stage': 'permanent-acquire', 'completed': true}
                : {'error': 'invalid stage request'},
          ),
        );
        await request.response.close();
        received.complete((
          length: length,
          encoding: encoding,
          path: request.uri.path,
          body: body,
        ));
      });

      final response = await postNativeFocusStage(
        Uri.parse('http://127.0.0.1:${server.port}'),
        'permanent-acquire',
      );
      final request = await received.future;
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {
        'stage': 'permanent-acquire',
        'completed': true,
      });
      expect(request.length, utf8.encode(request.body).length.toString());
      expect(request.encoding, isNull);
      expect(request.path, '/permanent-acquire');
      expect(jsonDecode(request.body), {'stage': 'permanent-acquire'});
    },
  );
}
