import 'package:flutter/services.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

class MobileLanInterface {
  const MobileLanInterface({
    required this.id,
    required this.name,
    required this.subnet,
  });

  final String id;
  final String name;
  final LanSubnet subnet;
}

/// Reads the active Android route each time a companion connection is opened.
class AndroidLan {
  AndroidLan({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('meowwatch/lan_interfaces');

  final MethodChannel _channel;

  Future<List<MobileLanInterface>> list() async {
    final entries = await _channel.invokeListMethod<Object?>('listIPv4');
    if (entries == null) throw const NearbyException('lan_unavailable');
    final interfaces = <MobileLanInterface>[];
    for (final entry in entries) {
      if (entry is! Map<Object?, Object?> ||
          entry['address'] is! String ||
          entry['prefixLength'] is! int ||
          entry['interfaceId'] is! String ||
          entry['friendlyName'] is! String ||
          (entry['interfaceId']! as String).isEmpty ||
          (entry['friendlyName']! as String).isEmpty) {
        throw const NearbyException('lan_unavailable');
      }
      interfaces.add(
        MobileLanInterface(
          id: entry['interfaceId']! as String,
          name: entry['friendlyName']! as String,
          subnet: LanSubnet(
            localAddress: LanIpv4Address.parse(entry['address']! as String),
            prefixLength: entry['prefixLength']! as int,
          ),
        ),
      );
    }
    return List.unmodifiable(interfaces);
  }

  Future<MobileLanInterface> routeFor(LanEndpoint endpoint) async {
    for (final route in await list()) {
      if (route.subnet.contains(endpoint.address)) return route;
    }
    throw const NearbyException('lan_unavailable');
  }
}
