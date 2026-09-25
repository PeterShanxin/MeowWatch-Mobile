import 'primitives.dart';

/// Numeric IPv4 only: no hostnames, mapped IPv6, octal or alternate IP syntax.
final class LanIpv4Address {
  LanIpv4Address._(this.value);
  final int value;

  factory LanIpv4Address.parse(String address) {
    final parts = address.split('.');
    if (parts.length != 4) throw const NearbyException('lan_unavailable');
    var value = 0;
    for (final part in parts) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) {
        throw const NearbyException('lan_unavailable');
      }
      final octet = int.parse(part);
      if (octet > 255) throw const NearbyException('lan_unavailable');
      value = (value << 8) | octet;
    }
    final private =
        value >> 24 == 10 ||
        value >> 20 == 0xac1 ||
        value >> 16 == 0xc0a8 ||
        value >> 16 == 0xa9fe;
    if (!private) throw const NearbyException('lan_unavailable');
    return LanIpv4Address._(value);
  }

  @override
  String toString() => [24, 16, 8, 0].map((s) => (value >> s) & 255).join('.');
}

final class LanSubnet {
  LanSubnet({required this.localAddress, required this.prefixLength}) {
    if (prefixLength < 1 || prefixLength > 30 || !contains(localAddress)) {
      throw const NearbyException('lan_unavailable');
    }
  }
  final LanIpv4Address localAddress;
  final int prefixLength;
  int get _mask => (0xffffffff << (32 - prefixLength)) & 0xffffffff;
  bool contains(LanIpv4Address peer) {
    if (prefixLength < 1 || prefixLength > 30) return false;
    final network = localAddress.value & _mask;
    final broadcast = network | (0xffffffff ^ _mask);
    return peer.value & _mask == network &&
        peer.value != network &&
        peer.value != broadcast;
  }

  void requirePeer(String address) {
    if (!contains(LanIpv4Address.parse(address))) {
      throw const NearbyException('lan_unavailable');
    }
  }
}

final class LanEndpoint {
  LanEndpoint({required this.address, required this.port}) {
    if (port < 1 || port > 65535) {
      throw const NearbyException('invalid_argument');
    }
  }
  final LanIpv4Address address;
  final int port;
}
