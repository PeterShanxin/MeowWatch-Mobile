import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Deliberately contains only a public error code, never the offending payload.
final class NearbyException implements Exception {
  const NearbyException(this.code);
  final String code;
  @override
  String toString() => 'NearbyException($code)';
}

abstract interface class MonotonicClock {
  Duration get now;
}

final class StopwatchClock implements MonotonicClock {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  Duration get now => _watch.elapsed;
}

abstract interface class SecureRandom {
  Uint8List bytes(int length);
}

final class SystemSecureRandom implements SecureRandom {
  final Random _random = Random.secure();
  @override
  Uint8List bytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

String encodeBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List decodeBytes(String value, int length) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) ||
      value.length != (length * 8 + 5) ~/ 6) {
    throw const NearbyException('invalid_argument');
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != length || encodeBytes(bytes) != value) {
      throw const NearbyException('invalid_argument');
    }
    return bytes;
  } on FormatException {
    throw const NearbyException('invalid_argument');
  }
}

Uint8List immutableBytes(List<int> bytes, int length) {
  if (bytes.length != length || bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const NearbyException('invalid_argument');
  }
  return Uint8List.fromList(bytes).asUnmodifiableView();
}

bool constantTimeEqual(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

void validateName(String name) {
  if (name.trim().isEmpty ||
      name.runes.length > 64 ||
      name.runes.any((r) => r < 32 || r == 127)) {
    throw const NearbyException('invalid_argument');
  }
}
