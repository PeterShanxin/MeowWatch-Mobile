import 'dart:convert';
import 'dart:io';

Future<({int statusCode, String body})> postNativeFocusStage(
  Uri bridge,
  String stage,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(Uri.parse('$bridge/$stage'));
    final body = utf8.encode(jsonEncode({'stage': stage}));
    request.headers.contentType = ContentType.json;
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 50));
    return (
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}
