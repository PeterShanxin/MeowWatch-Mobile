import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'primitives.dart';

Uint8List _lp(Iterable<List<int>> fields) {
  final result = BytesBuilder(copy: false);
  for (final field in fields) {
    result.add((ByteData(4)..setUint32(0, field.length)).buffer.asUint8List());
    result.add(field);
  }
  return result.takeBytes();
}

Uint8List _proof(
  List<int> key,
  String role,
  List<int> transcript, [
  List<List<int>> suffix = const [],
]) => Uint8List.fromList(
  Hmac(sha256, key).convert([
    ..._lp([utf8.encode(role)]),
    ...transcript,
    ..._lp(suffix),
  ]).bytes,
);

final class PairingTranscript {
  PairingTranscript({
    required String desktopId,
    required String pairId,
    required String clientId,
    required String clientName,
    required List<int> clientNonce,
    required List<int> serverNonce,
    required List<int> certificateSha256,
  }) {
    validateName(clientName);
    _bytes = _lp([
      utf8.encode('meowwatch-companion-pair'),
      utf8.encode('1'),
      decodeBytes(desktopId, 16),
      decodeBytes(pairId, 16),
      decodeBytes(clientId, 16),
      utf8.encode(clientName),
      immutableBytes(clientNonce, 32),
      immutableBytes(serverNonce, 32),
      immutableBytes(certificateSha256, 32),
    ]);
  }
  late final Uint8List _bytes;
  Uint8List clientProof(List<int> pairSecret) =>
      _proof(immutableBytes(pairSecret, 16), 'client', _bytes);
  Uint8List serverProof(
    List<int> pairSecret,
    String tokenId,
    List<int> deviceSecret,
  ) => _proof(immutableBytes(pairSecret, 16), 'server', _bytes, [
    decodeBytes(tokenId, 16),
    immutableBytes(deviceSecret, 32),
  ]);
}

final class AuthTranscript {
  AuthTranscript({
    required String desktopId,
    required String tokenId,
    required List<int> clientNonce,
    required List<int> serverNonce,
    required List<int> certificateSha256,
  }) : _bytes = _lp([
         utf8.encode('meowwatch-companion-auth'),
         utf8.encode('1'),
         decodeBytes(desktopId, 16),
         decodeBytes(tokenId, 16),
         immutableBytes(clientNonce, 32),
         immutableBytes(serverNonce, 32),
         immutableBytes(certificateSha256, 32),
       ]);
  final Uint8List _bytes;
  Uint8List clientProof(List<int> deviceSecret) =>
      _proof(immutableBytes(deviceSecret, 32), 'client', _bytes);
  Uint8List serverProof(List<int> deviceSecret, String connectionId) => _proof(
    immutableBytes(deviceSecret, 32),
    'server',
    _bytes,
    [decodeBytes(connectionId, 16)],
  );
}
