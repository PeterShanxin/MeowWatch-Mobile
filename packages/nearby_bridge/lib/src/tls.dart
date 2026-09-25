import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'primitives.dart';
import 'raw_secure_transport.dart';

const nearbyAlpn = 'meowwatch-companion/1';

/// Secret-bearing in-memory identity. Persistence belongs to a secure store.
final class TlsIdentity {
  TlsIdentity({required this.certificatePem, required this.privateKeyPem});
  final String certificatePem;
  final String privateKeyPem;
  Uint8List get certificateSha256 {
    final der = base64.decode(
      certificatePem
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll(RegExp(r'\s'), ''),
    );
    return Uint8List.fromList(sha256.convert(der).bytes);
  }

  SecurityContext createServerContext() =>
      SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
        ..setAlpnProtocols([nearbyAlpn], true)
        ..usePrivateKeyBytes(utf8.encode(privateKeyPem))
        ..useCertificateChainBytes(utf8.encode(certificatePem));

  /// Expensive key generation runs off the UI isolate. No files are written.
  static Future<TlsIdentity> generate({DateTime? notBefore, int days = 365}) {
    if (days < 1 || days > 365) throw const NearbyException('invalid_argument');
    return Isolate.run(() {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privateKey = pair.privateKey as RSAPrivateKey;
      final publicKey = pair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'MeowWatch Nearby'},
        privateKey,
        publicKey,
        signingAlgorithm: 'SHA-256',
      );
      final serialBytes = SystemSecureRandom().bytes(16);
      var serial = BigInt.zero;
      for (final byte in serialBytes) {
        serial = (serial << 8) | BigInt.from(byte);
      }
      serial |= BigInt.one;
      final certificate = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        days,
        serialNumber: serial.toString(),
        notBefore:
            notBefore ??
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        // basic_utils 5.8.2 emits nonzero unused KeyUsage BIT STRING bits;
        // BoringSSL rejects that DER. Omit the optional KeyUsage extension;
        // retain serverAuth EKU and explicit non-CA BasicConstraints.
        extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
        cA: false,
      );
      return TlsIdentity(
        certificatePem: certificate,
        privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
      );
    });
  }

  @override
  String toString() => 'TlsIdentity([REDACTED])';
}

bool _matches(X509Certificate certificate, List<int> pin, DateTime now) =>
    !now.isBefore(certificate.startValidity) &&
    now.isBefore(certificate.endValidity) &&
    constantTimeEqual(sha256.convert(certificate.der).bytes, pin);

/// TLS-only primitive. The caller must validate the numeric destination with
/// [LanSubnet] before opening it; tests can exercise this transport on loopback.
/// No application bytes are sent. Manual provisional pairing is intentionally
/// not exposed by this function: it always requires an out-of-band pin.
Future<RawSecureTransport> connectPinnedTls({
  required InternetAddress address,
  required int port,
  required List<int> certificateSha256,
  Duration timeout = const Duration(seconds: 5),
}) async => startPinnedTls(
  address: address,
  port: port,
  certificateSha256: certificateSha256,
  timeout: timeout,
).socket;

/// Owns a single TCP and TLS connection attempt until it succeeds or is
/// canceled. The deadline covers both phases and closes the underlying socket.
final class PinnedTlsAttempt {
  PinnedTlsAttempt._(this.address, this.port, this.pin, this.timeout) {
    _deadline = Timer(
      timeout,
      () => _finishError(TimeoutException('TLS connection timed out', timeout)),
    );
    unawaited(
      _connect().then<void>(
        _finishValue,
        onError: (Object error, StackTrace stack) => _finishError(error, stack),
      ),
    );
  }

  final InternetAddress address;
  final int port;
  final Uint8List pin;
  final Duration timeout;
  final _result = Completer<RawSecureTransport>();
  late final Timer _deadline;
  ConnectionTask<RawSocket>? _connectionTask;
  RawSocket? _raw;
  bool _finished = false;

  Future<RawSecureTransport> get socket => _result.future;

  void cancel() => _finishError(const NearbyException('cancelled'));

  Future<RawSecureTransport> _connect() async {
    final task = await RawSocket.startConnect(address, port);
    if (_finished) {
      task.cancel();
      throw const NearbyException('cancelled');
    }
    _connectionTask = task;
    final raw = await task.socket;
    if (_finished) {
      unawaited(raw.close());
      throw const NearbyException('cancelled');
    }
    _raw = raw;
    final secure = await RawSecureSocket.secure(
      raw,
      context: SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2,
      supportedProtocols: [nearbyAlpn],
      onBadCertificate: (cert) => _matches(cert, pin, DateTime.now().toUtc()),
    );
    if (_finished) {
      unawaited(secure.close());
      unawaited(raw.close());
      throw const NearbyException('cancelled');
    }
    final cert = secure.peerCertificate;
    if (cert == null ||
        !_matches(cert, pin, DateTime.now().toUtc()) ||
        secure.selectedProtocol != nearbyAlpn) {
      unawaited(secure.close());
      throw const NearbyException('auth_failed');
    }
    return RawSecureTransport(raw, secure);
  }

  void _finishValue(RawSecureTransport transport) {
    if (_finished) {
      transport.destroy();
      return;
    }
    _finished = true;
    _deadline.cancel();
    _result.complete(transport);
  }

  void _finishError(Object error, [StackTrace? stack]) {
    if (_finished) return;
    _finished = true;
    _deadline.cancel();
    final raw = _raw;
    if (raw != null) {
      unawaited(raw.close());
    } else {
      _connectionTask?.cancel();
    }
    _result.completeError(error, stack);
  }
}

PinnedTlsAttempt startPinnedTls({
  required InternetAddress address,
  required int port,
  required List<int> certificateSha256,
  Duration timeout = const Duration(seconds: 5),
}) => PinnedTlsAttempt._(
  address,
  port,
  immutableBytes(certificateSha256, 32),
  timeout,
);
