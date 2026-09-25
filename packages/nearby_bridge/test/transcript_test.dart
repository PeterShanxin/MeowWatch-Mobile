import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:test/test.dart';

void main() {
  String id(int byte) => encodeBytes(List.filled(16, byte));
  PairingTranscript transcript({
    int pin = 6,
    String name = 'Phone',
    int nonce = 4,
  }) => PairingTranscript(
    desktopId: id(1),
    pairId: id(2),
    clientId: id(3),
    clientName: name,
    clientNonce: List.filled(32, nonce),
    serverNonce: List.filled(32, 5),
    certificateSha256: List.filled(32, pin),
  );
  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final secret = List.filled(16, 7);

  test('LP HMAC matches independent Python hashlib vector', () {
    expect(
      hex(transcript().clientProof(secret)),
      '142f4031f72417aac1f540236b78e07f30ba28b16c0e3856bcc000a5ba894f76',
    );
    expect(
      hex(transcript().serverProof(secret, id(8), List.filled(32, 9))),
      '9a158ff400f6c4bd71415afa253fa4217752ce7fc325dc6954692946687c9e22',
    );
  });
  test(
    'MITM cert substitution, identity/nonce tamper and role reflection fail',
    () {
      final proof = transcript().clientProof(secret);
      for (final changed in [
        transcript(pin: 7),
        transcript(name: 'Other'),
        transcript(nonce: 8),
      ]) {
        expect(constantTimeEqual(proof, changed.clientProof(secret)), isFalse);
      }
      expect(
        constantTimeEqual(
          proof,
          transcript().serverProof(secret, id(8), List.filled(32, 9)),
        ),
        isFalse,
      );
      expect(constantTimeEqual(proof, proof.take(31).toList()), isFalse);
    },
  );
  test('auth domain and server connection ID are cryptographically bound', () {
    final auth = AuthTranscript(
      desktopId: id(1),
      tokenId: id(2),
      clientNonce: List.filled(32, 4),
      serverNonce: List.filled(32, 5),
      certificateSha256: List.filled(32, 6),
    );
    final deviceSecret = List.filled(32, 9);
    expect(
      auth.serverProof(deviceSecret, id(8)),
      isNot(auth.serverProof(deviceSecret, id(7))),
    );
    expect(
      auth.clientProof(deviceSecret),
      isNot(auth.serverProof(deviceSecret, id(8))),
    );
    expect(
      auth.clientProof(deviceSecret),
      isNot(transcript().clientProof(secret)),
    );
  });
}
