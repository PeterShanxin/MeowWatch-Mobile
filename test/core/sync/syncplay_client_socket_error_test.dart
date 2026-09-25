import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

void main() {
  test(
    'abort during plaintext STARTTLS fails closed without an uncaught error',
    () async {
      final uncaught = await _uncaughtDuring(() async {
        final server = await RawServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final accepted = <RawSocket>[];
        final plainBytes = <int>[];
        final logs = <String>[];
        final client = SyncplayClient(
          livenessTimeout: const Duration(seconds: 3),
          onLog: logs.add,
        );
        addTearDown(() async {
          await client.dispose();
          for (final socket in accepted) {
            socket.close();
          }
          await server.close();
        });

        server.listen((socket) {
          accepted.add(socket);
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            final bytes = socket.read();
            if (bytes == null) return;
            plainBytes.addAll(bytes);
            if (utf8
                .decode(plainBytes, allowMalformed: true)
                .contains('startTLS')) {
              _abortRaw(socket);
            }
          }, onError: (Object _) {});
        });

        await client.connect(
          server: '127.0.0.1',
          port: server.port,
          username: 'plain-probe',
          room: 'private-room',
          password: 'must-stay-secret',
        );
        await _until(
          () =>
              client.lastConnectionState?.status == SyncConnectionStatus.error,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final wire = utf8.decode(plainBytes, allowMalformed: true);
        expect(wire, contains('startTLS'));
        expect(wire, isNot(contains('Hello')));
        expect(wire, isNot(contains('must-stay-secret')));
        expect(client.debugChannelSecure, isFalse);
        expect(client.debugReconnectScheduled, isFalse);
        expect(
          logs.any(
            (line) =>
                line == 'tls negotiation closed before an answer' ||
                line.startsWith('tls negotiation error:'),
          ),
          isTrue,
        );
      });
      expect(
        uncaught,
        isEmpty,
        reason: 'the socket read error also fails its IOSink.done future',
      );
    },
    skip: !(Platform.isWindows || Platform.isLinux),
  );

  test(
    'abort after real TLS Hello schedules one reconnect without an uncaught error',
    () async {
      final identity = await TlsIdentity.generate();
      final uncaught = await _uncaughtDuring(() async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = <Socket>[];
        final upgraded = Completer<SecureSocket>();
        final sawHello = Completer<void>();
        final aborted = Completer<void>();
        final plainBytes = <int>[];
        final logs = <String>[];
        final serverSinkErrors = <Object>[];
        final statuses = <SyncConnectionStatus>[];
        final client = SyncplayClient(
          livenessTimeout: const Duration(seconds: 10),
          onLog: logs.add,
          shouldLog: ({required verboseOnly}) => !verboseOnly,
          secureUpgrade: (plain, subscription, {required host}) =>
              RawSecureSocket.secure(
                plain,
                subscription: subscription,
                host: host,
                context: SecurityContext(withTrustedRoots: false),
                onBadCertificate: (cert) => constantTimeEqual(
                  sha256.convert(cert.der).bytes,
                  identity.certificateSha256,
                ),
              ),
        );
        client.connectionState.listen((state) => statuses.add(state.status));
        addTearDown(() async {
          await client.dispose();
          for (final socket in accepted) {
            socket.destroy();
          }
          await server.close();
        });

        server.listen((socket) {
          accepted.add(socket);
          // Keep server-side sink failures separate from the client's zone.
          socket.done.then<void>(
            (_) {},
            onError: (Object error) {
              serverSinkErrors.add(error);
            },
          );
          var replied = false;
          socket.listen((bytes) {
            if (replied) return;
            plainBytes.addAll(bytes);
            if (!utf8
                .decode(plainBytes, allowMalformed: true)
                .contains('startTLS')) {
              return;
            }
            replied = true;
            unawaited(
              () async {
                socket.add(utf8.encode('{"TLS":{"startTLS":"true"}}\r\n'));
                await socket.flush();
                final secure = await SecureSocket.secureServer(
                  socket,
                  identity.createServerContext(),
                );
                accepted.add(secure);
                secure.done.then<void>(
                  (_) {},
                  onError: (Object error) {
                    serverSinkErrors.add(error);
                  },
                );
                upgraded.complete(secure);
                secure.listen((bytes) {
                  final line = utf8.decode(bytes, allowMalformed: true);
                  if (line.contains('Hello') && !sawHello.isCompleted) {
                    sawHello.complete();
                    secure.add(
                      utf8.encode('{"Hello":{"username":"tls-probe"}}\r\n'),
                    );
                  } else if (line.contains('"Chat"') && !aborted.isCompleted) {
                    _abort(secure);
                    aborted.complete();
                  }
                }, onError: (Object _) {});
              }().catchError((Object error, StackTrace stack) {
                if (!upgraded.isCompleted) upgraded.completeError(error, stack);
              }),
            );
          }, onError: (Object _) {});
        });

        await client.connect(
          server: '127.0.0.1',
          port: server.port,
          username: 'tls-probe',
          room: 'private-room',
          password: 'must-stay-secret',
        );
        await sawHello.future.timeout(const Duration(seconds: 8));
        await _until(() => statuses.contains(SyncConnectionStatus.connected));
        expect(client.debugChannelSecure, isTrue);
        expect(
          utf8.decode(plainBytes, allowMalformed: true),
          isNot(contains('must-stay-secret')),
        );

        await upgraded.future.timeout(const Duration(seconds: 1));
        final payload = 'x' * (1 << 20);
        for (var i = 0; i < 16; i++) {
          client.sendChat(payload);
        }
        await aborted.future.timeout(const Duration(seconds: 5));
        await _until(
          () => statuses.contains(SyncConnectionStatus.reconnecting),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          statuses.where(
            (status) => status == SyncConnectionStatus.reconnecting,
          ),
          hasLength(1),
        );
        expect(client.debugReconnectAttempt, 1);
        expect(client.debugReconnectScheduled, isTrue);
        expect(serverSinkErrors, isEmpty);
        expect(
          logs,
          contains(
            predicate<String>((line) => line.startsWith('socket error:')),
          ),
        );
      });
      expect(
        uncaught,
        isEmpty,
        reason: 'the TLS socket read error also fails its IOSink.done future',
      );
    },
    skip: !(Platform.isWindows || Platform.isLinux),
  );
}

void _abort(Socket socket) {
  // SO_LINGER with zero timeout sends TCP RST rather than an orderly FIN.
  // Winsock uses two ushort fields; Linux uses two int fields.
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

void _abortRaw(RawSocket socket) {
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
  socket.close();
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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
