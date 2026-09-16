import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_discovery.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_endpoints.dart';

import '../../support/sync_fakes.dart';

/// #234 + #265 — discovery is a real join. STARTTLS failures try the next
/// public candidate; a secure Hello that then refuses the room does not hop.
void main() {
  const timeout = Duration(milliseconds: 400);
  const config = RoomConfig(
    server: 'syncplay.pl',
    port: 8995,
    room: 'cozy-room',
    username: 'lin',
    endpointPolicy: SyncplayEndpointPolicy.discover,
  );

  group('a candidate does not count as working when', () {
    test('nothing is listening on the port', () async {
      final probeSocket = await ServerSocket.bind('127.0.0.1', 0);
      final port = probeSocket.port;
      await probeSocket.close();

      final outcome = await _joinAgainst([
        SyncplayEndpoint(host: '127.0.0.1', port: port),
      ], timeout: timeout);

      expect(outcome.join, isNull);
      expect(outcome.error, kNoSyncplayServerMessage);
    });

    test('the socket opens but the server never speaks', () async {
      final listener = await _Listener.start(reply: (_) => null);

      final outcome = await _joinAgainst([listener.endpoint], timeout: timeout);

      expect(outcome.join, isNull);
      expect(listener.receivedStartTlsRequest, isTrue);
      await listener.expectClientHungUp();
    });

    test('the listener speaks something other than Syncplay', () async {
      final listener = await _Listener.start(
        reply: (_) => json.encode({'not-a-syncplay-frame': true}),
      );

      final outcome = await _joinAgainst([listener.endpoint], timeout: timeout);

      expect(outcome.join, isNull);
      await listener.expectClientHungUp();
    });

    test('the server declines to encrypt', () async {
      final listener = await _Listener.start(
        reply: (_) => json.encode({
          'TLS': {'startTLS': 'false'},
        }),
      );

      final outcome = await _joinAgainst([listener.endpoint], timeout: timeout);

      expect(outcome.join, isNull);
      expect(
        listener.plaintextFromClient,
        isNot(contains('Hello')),
        reason: 'nothing may follow a refused upgrade',
      );
      await listener.expectClientHungUp();
    });

    test('the server skips the answer and just says Hello', () async {
      final listener = await _Listener.start(
        reply: (_) => json.encode({
          'Hello': {'username': 'lin'},
        }),
      );

      final outcome = await _joinAgainst([listener.endpoint], timeout: timeout);

      expect(outcome.join, isNull);
      await listener.expectClientHungUp();
    });

    test('a malformed STARTTLS answer is not a working endpoint', () async {
      final listener = await _Listener.start(reply: (_) => 'not json at all');

      final outcome = await _joinAgainst([listener.endpoint], timeout: timeout);

      expect(outcome.join, isNull);
      await listener.expectClientHungUp();
    });
  });

  group('walk decisions', () {
    test(
      'an unreachable candidate is disposed and the next is tried',
      () async {
        final first = await _Listener.start(
          reply: (_) => json.encode({
            'TLS': {'startTLS': 'false'},
          }),
        );
        final secondDead = await ServerSocket.bind('127.0.0.1', 0);
        final secondPort = secondDead.port;
        await secondDead.close();

        final created = <SyncplayClient>[];
        final second = SyncplayEndpoint(host: '127.0.0.1', port: secondPort);
        final outcome = await joinFirstWorkingEndpoint(
          config: config,
          settings: FakeEndpointSettings(),
          candidates: [first.endpoint, second],
          createClient: () {
            final client = SyncplayClient(livenessTimeout: timeout);
            created.add(client);
            return client;
          },
          connectUntilJoin: (client, endpoint) => client.connectUntilJoin(
            server: endpoint.host,
            port: endpoint.port,
            username: config.username,
            room: config.room,
          ),
          onLog: (_) {},
        );

        expect(outcome.join, isNull);
        expect(created, hasLength(2));
        expect(first.receivedStartTlsRequest, isTrue);
        await first.expectClientHungUp();
        for (final client in created) {
          expect(
            client.debugReconnectScheduled,
            isFalse,
            reason: 'a failed candidate must not keep a reconnect timer',
          );
        }
      },
    );

    test('a Hello that refuses the room does not hop', () async {
      final tried = <SyncplayEndpoint>[];
      final created = <SyncplayClient>[];
      const a = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);
      const b = SyncplayEndpoint(host: 'syncplay.pl', port: 8996);

      final outcome = await joinFirstWorkingEndpoint(
        config: config,
        settings: FakeEndpointSettings(),
        createClient: () {
          final client = SyncplayClient(livenessTimeout: timeout);
          created.add(client);
          return client;
        },
        connectUntilJoin: (client, endpoint) async {
          tried.add(endpoint);
          client.debugMarkLoggedIn('lin');
          return 'room is full';
        },
      );

      expect(outcome.join, isNull);
      expect(outcome.error, 'room is full');
      expect(tried, [a], reason: 'hopping would split two peers');
      expect(tried, isNot(contains(b)));
      expect(
        identical(outcome.retainedClient, created.single),
        isTrue,
        reason: 'Hello-then-Error may already have handed the client over',
      );
      expect(created.single.debugReconnectScheduled, isFalse);
      await created.single.dispose();
    });

    test('the first secure Hello keeps that client', () async {
      final settings = FakeEndpointSettings();
      final created = <SyncplayClient>[];
      const winner = SyncplayEndpoint(host: 'syncplay.pl', port: 8996);

      final outcome = await joinFirstWorkingEndpoint(
        config: config,
        settings: settings,
        createClient: () {
          final client = SyncplayClient(livenessTimeout: timeout);
          created.add(client);
          return client;
        },
        connectUntilJoin: (client, endpoint) async {
          if (endpoint.port == 8995) return 'declined STARTTLS';
          client.debugMarkLoggedIn('lin');
          return null;
        },
      );

      expect(outcome.join, isNotNull);
      expect(outcome.join!.endpoint, winner);
      expect(outcome.join!.config.server, winner.host);
      expect(outcome.join!.config.port, winner.port);
      expect(identical(outcome.join!.client, created.last), isTrue);
      expect(
        await settings.get(kSyncplayEndpointSettingKey),
        winner.toString(),
      );
    });
  });

  group('a pinned lobby join', () {
    test('a public Hello overwrites a stale remembered winner', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, 'syncplay.pl:8999');
      final created = <SyncplayClient>[];
      const pin = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);

      final outcome = await joinPinnedEndpoint(
        config: RoomConfig(
          server: pin.host,
          port: pin.port,
          room: 'mw272bare',
          username: 'lin',
          endpointPolicy: SyncplayEndpointPolicy.pinned,
        ),
        settings: settings,
        createClient: () {
          final client = SyncplayClient(livenessTimeout: timeout);
          created.add(client);
          return client;
        },
        connectUntilJoin: (client, endpoint) async {
          expect(endpoint, pin);
          client.debugMarkLoggedIn('lin');
          return null;
        },
      );

      expect(outcome.join, isNotNull);
      expect(outcome.join!.endpoint, pin);
      expect(outcome.join!.config.port, 8995);
      expect(
        await settings.get(kSyncplayEndpointSettingKey),
        'syncplay.pl:8995',
      );
      await created.single.dispose();
    });

    test('a self-hosted pin leaves the remembered winner alone', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, 'syncplay.pl:8999');
      final created = <SyncplayClient>[];

      final outcome = await joinPinnedEndpoint(
        config: const RoomConfig(
          server: 'cozy.example.net',
          port: 8999,
          room: 'lan-room',
          username: 'lin',
          endpointPolicy: SyncplayEndpointPolicy.pinned,
        ),
        settings: settings,
        createClient: () {
          final client = SyncplayClient(livenessTimeout: timeout);
          created.add(client);
          return client;
        },
        connectUntilJoin: (client, endpoint) async {
          client.debugMarkLoggedIn('lin');
          return null;
        },
      );

      expect(outcome.join, isNotNull);
      expect(outcome.join!.config.server, 'cozy.example.net');
      expect(
        await settings.get(kSyncplayEndpointSettingKey),
        'syncplay.pl:8999',
      );
      await created.single.dispose();
    });

    test('a refused Hello does not rewrite the remembered winner', () async {
      final settings = FakeEndpointSettings();
      await settings.set(kSyncplayEndpointSettingKey, 'syncplay.pl:8999');
      final created = <SyncplayClient>[];

      final outcome = await joinPinnedEndpoint(
        config: const RoomConfig(
          server: 'syncplay.pl',
          port: 8995,
          room: 'mw272bare',
          username: 'lin',
          endpointPolicy: SyncplayEndpointPolicy.pinned,
        ),
        settings: settings,
        createClient: () {
          final client = SyncplayClient(livenessTimeout: timeout);
          created.add(client);
          return client;
        },
        connectUntilJoin: (client, endpoint) async {
          client.debugMarkLoggedIn('lin');
          return 'room is full';
        },
      );

      expect(outcome.join, isNull);
      expect(outcome.error, 'room is full');
      expect(
        await settings.get(kSyncplayEndpointSettingKey),
        'syncplay.pl:8999',
      );
      await created.single.dispose();
    });
  });
}

Future<SyncedJoinOutcome> _joinAgainst(
  List<SyncplayEndpoint> candidates, {
  required Duration timeout,
}) {
  return joinFirstWorkingEndpoint(
    config: RoomConfig(
      server: candidates.first.host,
      port: candidates.first.port,
      room: 'cozy-room',
      username: 'lin',
      endpointPolicy: SyncplayEndpointPolicy.discover,
    ),
    settings: FakeEndpointSettings(),
    candidates: candidates,
    createClient: () => SyncplayClient(livenessTimeout: timeout),
    connectUntilJoin: (client, endpoint) => client.connectUntilJoin(
      server: endpoint.host,
      port: endpoint.port,
      username: 'lin',
      room: 'cozy-room',
    ),
  );
}

/// A loopback listener that answers the client's STARTTLS request with a
/// scripted [reply] (null to stay silent).
class _Listener {
  _Listener._(this._server);

  static Future<_Listener> start({
    required String? Function(String request) reply,
  }) async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final listener = _Listener._(server);
    server.listen((socket) {
      listener._accepted.add(socket);
      final closed = Completer<void>();
      listener._closed.add(closed.future);
      socket.listen(
        (bytes) {
          final text = utf8.decode(bytes, allowMalformed: true);
          listener.plaintextFromClient += text;
          if (!text.contains('startTLS')) return;
          listener.receivedStartTlsRequest = true;
          final answer = reply(text);
          if (answer == null) return;
          try {
            socket.add(utf8.encode('$answer\r\n'));
          } on Object {
            // The client may already be gone; nothing to assert here.
          }
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        },
        cancelOnError: false,
      );
    });
    addTearDown(listener._close);
    return listener;
  }

  final ServerSocket _server;
  final List<Socket> _accepted = <Socket>[];
  final List<Future<void>> _closed = <Future<void>>[];

  String plaintextFromClient = '';
  bool receivedStartTlsRequest = false;

  SyncplayEndpoint get endpoint =>
      SyncplayEndpoint(host: '127.0.0.1', port: _server.port);

  Future<void> expectClientHungUp() async {
    expect(_accepted, isNotEmpty, reason: 'the join never connected');
    await Future.wait(_closed).timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('the join left its socket open'),
    );
  }

  Future<void> _close() async {
    for (final socket in _accepted) {
      socket.destroy();
    }
    await _server.close();
  }
}
