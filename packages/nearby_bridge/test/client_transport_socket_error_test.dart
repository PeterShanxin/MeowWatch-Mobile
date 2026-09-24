import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nearby_bridge/src/client_transport.dart';
import 'package:nearby_bridge/src/tls.dart';
import 'package:nearby_bridge/src/wire.dart';
import 'package:test/test.dart';

void main() {
  test(
    'real TLS write abort closes the transport without an uncaught sink error',
    () async {
      final identity = await TlsIdentity.generate();
      final uncaught = await _uncaughtDuring(() async {
        final listener = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
          identity.createServerContext(),
          supportedProtocols: [nearbyAlpn],
        );
        final peers = <SecureSocket>[];
        final aborted = Completer<void>();
        final closed = Completer<String>();
        addTearDown(() async {
          for (final peer in peers) {
            peer.destroy();
          }
          await listener.close();
        });
        listener.listen((peer) {
          peers.add(peer);
          unawaited(
            peer.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
          peer.listen((_) {
            if (aborted.isCompleted) return;
            _abort(peer);
            aborted.complete();
          }, onError: (Object _) {});
        }, onError: (Object _) {});

        final socket = await connectPinnedTls(
          address: InternetAddress.loopbackIPv4,
          port: listener.port,
          certificateSha256: identity.certificateSha256,
        );
        final transport = ClientTransport(socket);
        addTearDown(() => transport.close('not_connected'));
        transport.onClosed = (code) {
          if (!closed.isCompleted) closed.complete(code);
        };
        final frame = NearbyFrame({
          'v': 1,
          'type': 'ping',
          'payload': List.filled(8, 'x' * 3900),
        });
        final writes = <Future<void>>[];
        final writeErrors = <Object>[];
        for (var i = 0; i < 7; i++) {
          writes.add(transport.send(frame).catchError(writeErrors.add));
        }
        await aborted.future.timeout(const Duration(seconds: 5));
        expect(
          await closed.future.timeout(const Duration(seconds: 5)),
          'not_connected',
        );
        await Future.wait(writes);
        expect(writeErrors, isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(uncaught, isEmpty);
    },
    skip: !(Platform.isWindows || Platform.isLinux),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _abort(Socket socket) {
  final value = Uint8List(Platform.isWindows ? 4 : 8);
  final linger = ByteData.view(value.buffer);
  if (Platform.isWindows) {
    linger.setUint16(0, 1, Endian.host);
    linger.setUint16(2, 0, Endian.host);
  } else {
    linger.setInt32(0, 1, Endian.host);
    linger.setInt32(4, 0, Endian.host);
  }
  socket.setRawOption(
    RawSocketOption(
      RawSocketOption.levelSocket,
      Platform.isWindows ? 0x80 : 13,
      value,
    ),
  );
  socket.destroy();
}

Future<List<Object>> _uncaughtDuring(Future<void> Function() action) async {
  final errors = <Object>[];
  final completed = Completer<void>();
  runZonedGuarded(() {
    unawaited(() async {
      try {
        await action();
        completed.complete();
      } catch (error, stack) {
        completed.completeError(error, stack);
      }
    }());
  }, (error, _) => errors.add(error));
  await completed.future;
  return errors;
}
