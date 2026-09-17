import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';

void main() {
  test('registers only the bounded non-secret MeowWatch TXT fields', () async {
    final backend = _FakeMdnsBackend();
    final registration = NearbyAdvertisementRegistration(
      desktopId: _id(1),
      displayName: 'Living room',
      port: 43123,
      pairingOpen: true,
      backend: backend,
    );

    await registration.start();

    final service = backend.registered.single;
    expect(service.type, nearbyMdnsServiceType);
    expect(service.name, 'Living room');
    expect(service.txt.keys, unorderedEquals(['v', 'id', 'pairing', 'name']));
    expect(utf8.decode(service.txt['v']!), nearbyMdnsProtocolVersion);
    expect(utf8.decode(service.txt['pairing']!), '1');
    expect(service.txt.toString(), isNot(contains('secret')));
    await registration.stop();
    expect(backend.unregistered, [backend.registrationHandle]);
  });

  test('emits valid advertisements while keeping addresses as hints', () async {
    final backend = _FakeMdnsBackend();
    final discovery = NearbyDiscovery(backend: backend);
    final event = expectLater(
      discovery.events,
      emits(
        isA<NearbyDiscoveryEvent>()
            .having((value) => value.status, 'status', NearbyMdnsStatus.found)
            .having(
              (value) => value.advertisement.desktopId,
              'desktopId',
              _id(2),
            )
            .having(
              (value) => value.advertisement.addressHints,
              'addressHints',
              ['203.0.113.10'],
            ),
      ),
    );
    await discovery.start();

    backend.emit(
      _record(desktopId: _id(2), addressHints: const ['203.0.113.10']),
      NearbyMdnsStatus.found,
    );

    await event;
    await discovery.dispose();
  });

  test('ignores malformed or wrong-version advertisements', () async {
    final backend = _FakeMdnsBackend();
    final discovery = NearbyDiscovery(backend: backend);
    final received = <NearbyDiscoveryEvent>[];
    final subscription = discovery.events.listen(received.add);
    await discovery.start();

    backend.emit(
      NearbyMdnsRecord(
        name: 'Bad',
        type: nearbyMdnsServiceType,
        port: 43123,
        txt: {
          'v': utf8.encode('2'),
          'id': utf8.encode(_id(3)),
          'pairing': utf8.encode('1'),
          'name': utf8.encode('Bad'),
        },
      ),
      NearbyMdnsStatus.found,
    );
    backend.emit(
      NearbyMdnsRecord(
        name: 'Secret bait',
        type: nearbyMdnsServiceType,
        port: 43123,
        txt: {'v': utf8.encode('1'), 'secret': List.filled(32, 7)},
      ),
      NearbyMdnsStatus.found,
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await subscription.cancel();
    await discovery.dispose();
  });

  test(
    'permission failure is explicit rather than an empty discovery',
    () async {
      final backend = _FakeMdnsBackend(
        discoveryError: const NearbyPlatformException('permission_denied'),
      );
      final discovery = NearbyDiscovery(backend: backend);

      await expectLater(
        discovery.start(),
        throwsA(
          isA<NearbyPlatformException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );
      expect(discovery.isRunning, isFalse);
      await discovery.dispose();
    },
  );

  test('stop cancels a pending discovery and cleans only its handle', () async {
    final gate = Completer<Object>();
    final backend = _FakeMdnsBackend(discoveryGate: gate);
    final discovery = NearbyDiscovery(backend: backend);

    final starting = discovery.start();
    final startExpectation = expectLater(
      starting,
      throwsA(
        isA<NearbyPlatformException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    final stopping = discovery.stop();
    final ownedHandle = Object();
    gate.complete(ownedHandle);

    await startExpectation;
    await stopping;
    expect(backend.stopped, [ownedHandle]);
    expect(discovery.isRunning, isFalse);
    await discovery.dispose();
  });

  test('stop cancels a pending registration and unregisters once', () async {
    final gate = Completer<Object>();
    final backend = _FakeMdnsBackend(registrationGate: gate);
    final registration = NearbyAdvertisementRegistration(
      desktopId: _id(4),
      displayName: 'Bedroom',
      port: 43124,
      pairingOpen: false,
      backend: backend,
    );

    final starting = registration.start();
    final startExpectation = expectLater(
      starting,
      throwsA(
        isA<NearbyPlatformException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    final stopping = registration.stop();
    final ownedHandle = Object();
    gate.complete(ownedHandle);

    await startExpectation;
    await stopping;
    expect(backend.unregistered, [ownedHandle]);
    await registration.dispose();
  });
}

NearbyMdnsRecord _record({
  required String desktopId,
  List<String> addressHints = const ['192.168.1.8'],
}) => NearbyMdnsRecord(
  name: 'Living room',
  type: nearbyMdnsServiceType,
  port: 43123,
  host: 'living-room.local',
  addressHints: addressHints,
  txt: {
    'v': utf8.encode(nearbyMdnsProtocolVersion),
    'id': utf8.encode(desktopId),
    'pairing': utf8.encode('1'),
    'name': utf8.encode('Living room'),
  },
);

String _id(int byte) => encodeBytes(List.filled(16, byte));

final class _FakeMdnsBackend implements NearbyMdnsBackend {
  _FakeMdnsBackend({
    this.discoveryError,
    this.discoveryGate,
    this.registrationGate,
  });

  final Object? discoveryError;
  final Completer<Object>? discoveryGate;
  final Completer<Object>? registrationGate;
  final Object registrationHandle = Object();
  final List<NearbyMdnsRecord> registered = [];
  final List<Object> unregistered = [];
  final List<Object> stopped = [];
  NearbyMdnsListener? listener;

  @override
  Future<Object> register(NearbyMdnsRecord service) {
    registered.add(service);
    return registrationGate?.future ?? Future.value(registrationHandle);
  }

  @override
  Future<Object> startDiscovery({
    required String serviceType,
    required NearbyMdnsListener listener,
  }) {
    expect(serviceType, nearbyMdnsServiceType);
    this.listener = listener;
    final error = discoveryError;
    if (error != null) return Future.error(error);
    return discoveryGate?.future ?? Future.value(Object());
  }

  void emit(NearbyMdnsRecord record, NearbyMdnsStatus status) {
    listener!(record, status);
  }

  @override
  Future<void> stopDiscovery(Object discovery) async {
    stopped.add(discovery);
  }

  @override
  Future<void> unregister(Object registration) async {
    unregistered.add(registration);
  }
}
