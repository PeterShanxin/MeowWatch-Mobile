import 'dart:convert';
import 'dart:io';

/// The bounded rendezvous accepts Content-Length, never chunked request bodies.
void writeFixtureJson(HttpClientRequest request, Map<String, Object?> payload) {
  final bytes = utf8.encode(jsonEncode(payload));
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  request.contentLength = bytes.length;
  request.add(bytes);
}
