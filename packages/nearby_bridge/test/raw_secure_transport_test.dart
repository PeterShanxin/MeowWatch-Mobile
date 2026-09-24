import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_bridge/transport.dart';
import 'package:test/test.dart';

void main() {
  test(
    'drained TLS close delivers queued bytes before immediate destroy',
    () async {
      final identity = await TlsIdentity.generate();
      final listener = await RawServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final accepted = Completer<(RawSocket, RawSecureSocket)>();
      final listenerSubscription = listener.listen((raw) {
        unawaited(
          RawSecureSocket.secureServer(
            raw,
            identity.createServerContext(),
            supportedProtocols: [nearbyAlpn],
          ).then(
            (secure) => accepted.complete((raw, secure)),
            onError: (Object error, StackTrace stack) =>
                accepted.completeError(error, stack),
          ),
        );
      });
      final client = await connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: listener.port,
        certificateSha256: identity.certificateSha256,
      );
      final (raw, secure) = await accepted.future;
      final transport = RawSecureTransport(raw, secure);
      addTearDown(() async {
        transport.destroy();
        client.destroy();
        await listenerSubscription.cancel();
        await listener.close();
      });

      final expected = Uint8List(64 * 1024 + 7);
      for (var i = 0; i < expected.length - 7; i++) {
        expected[i] = i % 251;
      }
      expected.setRange(
        expected.length - 7,
        expected.length,
        'leaving'.codeUnits,
      );
      final received = BytesBuilder(copy: false);
      final complete = Completer<void>();
      client.listen(
        (bytes) {
          if (complete.isCompleted) return;
          received.add(bytes);
          if (received.length >= expected.length) complete.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!complete.isCompleted) complete.completeError(error, stack);
        },
        onDone: () {
          if (!complete.isCompleted) {
            complete.completeError(const SocketException('peer closed early'));
          }
        },
      );
      transport.add(expected.sublist(0, expected.length - 7));
      transport.add(expected.sublist(expected.length - 7));
      await transport.close().timeout(const Duration(seconds: 5));
      transport.destroy();
      await complete.future.timeout(const Duration(seconds: 5));
      expect(received.length, expected.length);
      expect(sha256.convert(received.takeBytes()), sha256.convert(expected));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'paused real TLS peer backpressures partial writes without losing bytes; '
    'destroy rejects a pending flush',
    () async {
      final identity = await TlsIdentity.generate();
      final listener = await RawServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final accepted = Completer<(RawSocket, RawSecureSocket)>();
      final listenerSubscription = listener.listen((raw) {
        unawaited(
          RawSecureSocket.secureServer(
            raw,
            identity.createServerContext(),
            supportedProtocols: [nearbyAlpn],
          ).then(
            (secure) => accepted.complete((raw, secure)),
            onError: (Object error, StackTrace stack) =>
                accepted.completeError(error, stack),
          ),
        );
      });
      final client = await connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: listener.port,
        certificateSha256: identity.certificateSha256,
      );
      final (raw, secure) = await accepted.future;
      final transport = RawSecureTransport(raw, secure);
      addTearDown(() async {
        transport.destroy();
        client.destroy();
        await listenerSubscription.cancel();
        await listener.close();
      });

      final payload = Uint8List(8 * 1024 * 1024);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = i % 251;
      }
      final received = BytesBuilder(copy: false);
      final complete = Completer<void>();
      final subscription = client.listen(
        (bytes) {
          if (complete.isCompleted) return;
          received.add(bytes);
          if (received.length >= payload.length) complete.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!complete.isCompleted) complete.completeError(error, stack);
        },
        onDone: () {
          if (!complete.isCompleted) {
            complete.completeError(const SocketException('peer closed early'));
          }
        },
      );
      subscription.pause();
      transport.add(payload);
      var flushed = false;
      final flush = transport.flush().then((_) => flushed = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(flushed, false);
      subscription.resume();
      await flush.timeout(const Duration(seconds: 15));
      await complete.future.timeout(const Duration(seconds: 15));
      expect(received.length, payload.length);
      expect(sha256.convert(received.takeBytes()), sha256.convert(payload));

      subscription.pause();
      transport.add(payload);
      final canceledFlush = expectLater(
        transport.flush(),
        throwsA(isA<SocketException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      transport.destroy();
      await canceledFlush.timeout(const Duration(seconds: 3));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
