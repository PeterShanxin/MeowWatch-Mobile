import 'dart:convert';
import 'dart:typed_data';
import 'lan.dart';
import 'primitives.dart';

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String encodeManualCode(List<int> secret) {
  final bytes = immutableBytes(secret, 16);
  var bits = 0;
  var accumulator = 0;
  final out = StringBuffer();
  for (final byte in bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(accumulator >> bits) & 31]);
    }
    accumulator &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(accumulator << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List decodeManualCode(String code) {
  if (code.length > 40) throw const NearbyException('invalid_argument');
  final normalized = code.replaceAll(RegExp(r'[ -]'), '').toUpperCase();
  if (normalized.length != 26) throw const NearbyException('invalid_argument');
  var bits = 0;
  var accumulator = 0;
  final bytes = <int>[];
  for (final character in normalized.split('')) {
    final index = _alphabet.indexOf(character);
    if (index < 0) throw const NearbyException('invalid_argument');
    accumulator = (accumulator << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((accumulator >> bits) & 255);
    }
    accumulator &= (1 << bits) - 1;
  }
  if (accumulator != 0 || encodeManualCode(bytes) != normalized) {
    throw const NearbyException('invalid_argument');
  }
  return Uint8List.fromList(bytes);
}

/// Secret-bearing value. Explicit encode methods only; never log the result.
final class PairingInvitation {
  PairingInvitation({
    required this.desktopId,
    required this.pairId,
    required this.endpoint,
    required List<int> certificateSha256,
    required List<int> pairSecret,
  }) : certificateSha256 = immutableBytes(certificateSha256, 32),
       pairSecret = immutableBytes(pairSecret, 16) {
    decodeBytes(desktopId, 16);
    decodeBytes(pairId, 16);
  }
  final String desktopId;
  final String pairId;
  final LanEndpoint endpoint;
  final Uint8List certificateSha256;
  final Uint8List pairSecret;
  String get manualCode => encodeManualCode(pairSecret);

  String encodeQr() =>
      'meowwatch-pair:${encodeBytes(utf8.encode(jsonEncode({'v': 1, 'desktopId': desktopId, 'pairId': pairId, 'address': endpoint.address.toString(), 'port': endpoint.port, 'certificateSha256': encodeBytes(certificateSha256), 'pairSecret': encodeBytes(pairSecret)})))}';

  factory PairingInvitation.decodeQr(String encoded) {
    const prefix = 'meowwatch-pair:';
    if (encoded.length > 2048 || !encoded.startsWith(prefix)) {
      throw const NearbyException('invalid_argument');
    }
    try {
      final raw = encoded.substring(prefix.length);
      final bytes = base64Url.decode(base64Url.normalize(raw));
      if (encodeBytes(bytes) != raw) throw const FormatException();
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['v'] != 1 || data.length != 7) throw const FormatException();
      final invitation = PairingInvitation(
        desktopId: data['desktopId'] as String,
        pairId: data['pairId'] as String,
        endpoint: LanEndpoint(
          address: LanIpv4Address.parse(data['address'] as String),
          port: data['port'] as int,
        ),
        certificateSha256: decodeBytes(data['certificateSha256'] as String, 32),
        pairSecret: decodeBytes(data['pairSecret'] as String, 16),
      );
      // Canonical serialization also rejects duplicate/unknown keys.
      if (invitation.encodeQr() != encoded) throw const FormatException();
      return invitation;
    } on NearbyException {
      rethrow;
    } catch (_) {
      throw const NearbyException('invalid_argument');
    }
  }

  @override
  String toString() => 'PairingInvitation([REDACTED])';
}
