import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/nearby/android_lan.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meowwatch/lan_interfaces');
  final adapter = AndroidLan(channel: channel);
  List<Object?> entries = [];
  setUp(() {
    entries = [
      {
        'address': '192.168.42.12',
        'prefixLength': 24,
        'interfaceId': '42:wlan0',
        'friendlyName': 'Wi-Fi',
      },
    ];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'listIPv4');
      return entries;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('matches only peers on the current real interface prefix', () async {
    final route = await adapter.routeFor(
      LanEndpoint(address: LanIpv4Address.parse('192.168.42.50'), port: 5000),
    );
    expect(route.name, 'Wi-Fi');
    for (final address in ['192.168.43.50', '192.168.42.0', '192.168.42.255']) {
      await expectLater(
        adapter.routeFor(
          LanEndpoint(address: LanIpv4Address.parse(address), port: 5000),
        ),
        throwsA(isA<NearbyException>()),
      );
    }
  });

  test('re-reads routing instead of reusing a stale network', () async {
    final endpoint = LanEndpoint(
      address: LanIpv4Address.parse('192.168.42.50'),
      port: 5000,
    );
    await adapter.routeFor(endpoint);
    entries = [];
    await expectLater(
      adapter.routeFor(endpoint),
      throwsA(isA<NearbyException>()),
    );
  });

  test('malformed and public platform data cannot widen access', () async {
    for (final address in ['8.8.8.8', '127.0.0.1', '192.168.042.12']) {
      (entries.single! as Map<String, Object>)['address'] = address;
      await expectLater(adapter.list(), throwsA(isA<NearbyException>()));
    }
    entries = [
      {'address': '192.168.42.12', 'prefixLength': 0},
    ];
    await expectLater(adapter.list(), throwsA(isA<NearbyException>()));
  });

  test(
    'native permission denial remains distinct from empty discovery',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(code: 'permission_denied');
      });
      await expectLater(
        adapter.list(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'permission_denied',
          ),
        ),
      );
    },
  );
}
