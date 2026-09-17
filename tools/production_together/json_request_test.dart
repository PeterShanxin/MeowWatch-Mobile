import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'json_request.dart';

void main() {
  test(
    'rendezvous PUT sends a bounded UTF-8 body without chunked encoding',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      final payload = <String, Object?>{
        'runId': 'wire-contract',
        'role': 'host',
        'checkpoint': 'chat-sent',
        'value': 'Movie night 🎬 一起看',
      };
      final observed = server.first.then((request) async {
        expect(request.method, 'PUT');
        expect(
          request.headers.value(HttpHeaders.transferEncodingHeader),
          isNull,
        );
        expect(request.contentLength, utf8.encode(jsonEncode(payload)).length);
        expect(request.headers.contentType?.mimeType, 'application/json');
        expect(
          request.headers.value(HttpHeaders.cacheControlHeader),
          'no-store',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), payload);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      final request = await client.putUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/checkpoint?run=wire-contract',
        ),
      );
      writeFixtureJson(request, payload);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
      await observed;
    },
  );
}
