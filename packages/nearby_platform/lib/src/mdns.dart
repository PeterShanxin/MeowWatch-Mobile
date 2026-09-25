import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nsd/nsd.dart' as nsd;

const nearbyMdnsServiceType = '_meowwatch._tcp';
const nearbyMdnsProtocolVersion = '1';

final class NearbyPlatformException implements Exception {
  const NearbyPlatformException(this.code);

  final String code;

  @override
  String toString() => 'NearbyPlatformException($code)';
}

enum NearbyMdnsStatus { found, lost }

/// Raw mDNS data. Address and host values remain untrusted connection hints.
final class NearbyMdnsRecord {
  NearbyMdnsRecord({
    required this.name,
    required this.type,
    required this.port,
    required Map<String, List<int>?> txt,
    this.host,
    List<String> addressHints = const [],
  }) : txt = Map.unmodifiable({
         for (final entry in txt.entries)
           entry.key: entry.value == null
               ? null
               : List<int>.unmodifiable(entry.value!),
       }),
       addressHints = List.unmodifiable(addressHints);

  final String? name;
  final String? type;
  final String? host;
  final int? port;
  final Map<String, List<int>?> txt;
  final List<String> addressHints;
}

typedef NearbyMdnsListener =
    void Function(NearbyMdnsRecord record, NearbyMdnsStatus status);

/// Injectable boundary around the process-wide `nsd` plugin.
abstract interface class NearbyMdnsBackend {
  Future<Object> register(NearbyMdnsRecord service);
  Future<void> unregister(Object registration);
  Future<Object> startDiscovery({
    required String serviceType,
    required NearbyMdnsListener listener,
  });
  Future<void> stopDiscovery(Object discovery);
}

final class FlutterNsdBackend implements NearbyMdnsBackend {
  const FlutterNsdBackend();

  @override
  Future<Object> register(NearbyMdnsRecord service) => nsd.register(
    nsd.Service(
      name: service.name,
      type: service.type,
      port: service.port,
      txt: {
        for (final entry in service.txt.entries)
          entry.key: entry.value == null
              ? null
              : Uint8List.fromList(entry.value!),
      },
    ),
  );

  @override
  Future<void> unregister(Object registration) {
    if (registration is! nsd.Registration) {
      throw const NearbyPlatformException('lan_unavailable');
    }
    return nsd.unregister(registration);
  }

  @override
  Future<Object> startDiscovery({
    required String serviceType,
    required NearbyMdnsListener listener,
  }) async {
    final discovery = await nsd.startDiscovery(
      serviceType,
      autoResolve: true,
      ipLookupType: nsd.IpLookupType.v4,
    );
    void notify(nsd.Service service, nsd.ServiceStatus status) {
      listener(
        NearbyMdnsRecord(
          name: service.name,
          type: service.type,
          host: service.host,
          port: service.port,
          txt: service.txt ?? const {},
          addressHints:
              service.addresses?.map((address) => address.address).toList() ??
              const [],
        ),
        status == nsd.ServiceStatus.found
            ? NearbyMdnsStatus.found
            : NearbyMdnsStatus.lost,
      );
    }

    try {
      discovery.addServiceListener(notify);
      for (final service in discovery.services) {
        notify(service, nsd.ServiceStatus.found);
      }
    } catch (_) {
      discovery.removeServiceListener(notify);
      await nsd.stopDiscovery(discovery);
      rethrow;
    }
    return _FlutterDiscovery(discovery, notify);
  }

  @override
  Future<void> stopDiscovery(Object discovery) async {
    if (discovery is! _FlutterDiscovery) {
      throw const NearbyPlatformException('lan_unavailable');
    }
    discovery.discovery.removeServiceListener(discovery.listener);
    await nsd.stopDiscovery(discovery.discovery);
  }
}

final class _FlutterDiscovery {
  const _FlutterDiscovery(this.discovery, this.listener);
  final nsd.Discovery discovery;
  final nsd.ServiceListener listener;
}

final class NearbyAdvertisement {
  NearbyAdvertisement({
    required this.desktopId,
    required this.displayName,
    required this.pairingOpen,
    required this.port,
    required List<String> addressHints,
    this.hostHint,
  }) : addressHints = List.unmodifiable(addressHints);

  final String desktopId;
  final String displayName;
  final bool pairingOpen;
  final int port;

  /// Discovery hints only. Callers must validate the selected numeric address
  /// against their actual LAN interface and authenticate the TLS peer.
  final List<String> addressHints;
  final String? hostHint;
}

final class NearbyDiscoveryEvent {
  const NearbyDiscoveryEvent(this.advertisement, this.status);
  final NearbyAdvertisement advertisement;
  final NearbyMdnsStatus status;
}

final class NearbyDiscovery {
  factory NearbyDiscovery({
    NearbyMdnsBackend backend = const FlutterNsdBackend(),
  }) => NearbyDiscovery._(backend);

  NearbyDiscovery._(this._backend);

  final NearbyMdnsBackend _backend;
  final _events = StreamController<NearbyDiscoveryEvent>.broadcast();
  Object? _handle;
  Future<void>? _starting;
  bool _wantStarted = false;
  bool _disposed = false;
  int _generation = 0;

  Stream<NearbyDiscoveryEvent> get events => _events.stream;
  bool get isRunning => _handle != null;

  Future<void> start() {
    if (_disposed) {
      return Future.error(const NearbyPlatformException('disposed'));
    }
    if (_handle != null) return Future.value();
    final pending = _starting;
    if (pending != null) return pending;
    _wantStarted = true;
    final generation = ++_generation;
    final future = _start(generation);
    _starting = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_starting, future)) _starting = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_starting, future)) _starting = null;
        },
      ),
    );
    return future;
  }

  Future<void> _start(int generation) async {
    Object handle;
    try {
      handle = await _backend.startDiscovery(
        serviceType: nearbyMdnsServiceType,
        listener: (record, status) {
          if (_disposed || !_wantStarted || generation != _generation) return;
          final advertisement = _parseAdvertisement(record);
          if (advertisement != null) {
            _events.add(NearbyDiscoveryEvent(advertisement, status));
          }
        },
      );
    } catch (error) {
      throw _platformError(error);
    }
    if (_disposed || !_wantStarted || generation != _generation) {
      try {
        await _backend.stopDiscovery(handle);
      } catch (_) {
        throw const NearbyPlatformException('lan_unavailable');
      }
      throw const NearbyPlatformException('cancelled');
    }
    _handle = handle;
  }

  Future<void> stop() async {
    _wantStarted = false;
    _generation++;
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      try {
        await _backend.stopDiscovery(handle);
      } catch (error) {
        throw _platformError(error);
      }
    }
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } on NearbyPlatformException catch (error) {
        if (error.code != 'cancelled') rethrow;
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _events.close();
  }
}

final class NearbyAdvertisementRegistration {
  factory NearbyAdvertisementRegistration({
    required String desktopId,
    required String displayName,
    required int port,
    required bool pairingOpen,
    NearbyMdnsBackend backend = const FlutterNsdBackend(),
  }) => NearbyAdvertisementRegistration._(
    desktopId,
    displayName,
    port,
    pairingOpen,
    backend,
  );

  NearbyAdvertisementRegistration._(
    this.desktopId,
    this.displayName,
    this.port,
    this.pairingOpen,
    this._backend,
  ) {
    try {
      decodeBytes(desktopId, 16);
    } catch (_) {
      throw const NearbyPlatformException('invalid_argument');
    }
    _validateDisplayName(displayName);
    if (port < 1 || port > 65535) {
      throw const NearbyPlatformException('invalid_argument');
    }
  }

  final String desktopId;
  final String displayName;
  final int port;
  final bool pairingOpen;
  final NearbyMdnsBackend _backend;
  Object? _handle;
  Future<void>? _starting;
  bool _wantStarted = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isRunning => _handle != null;

  Future<void> start() {
    if (_disposed) {
      return Future.error(const NearbyPlatformException('disposed'));
    }
    if (_handle != null) return Future.value();
    final pending = _starting;
    if (pending != null) return pending;
    _wantStarted = true;
    final generation = ++_generation;
    final future = _start(generation);
    _starting = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_starting, future)) _starting = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_starting, future)) _starting = null;
        },
      ),
    );
    return future;
  }

  Future<void> _start(int generation) async {
    Object handle;
    try {
      handle = await _backend.register(
        NearbyMdnsRecord(
          name: displayName,
          type: nearbyMdnsServiceType,
          port: port,
          txt: {
            'v': utf8.encode(nearbyMdnsProtocolVersion),
            'id': utf8.encode(desktopId),
            'pairing': utf8.encode(pairingOpen ? '1' : '0'),
            'name': utf8.encode(displayName),
          },
        ),
      );
    } catch (error) {
      throw _platformError(error);
    }
    if (_disposed || !_wantStarted || generation != _generation) {
      try {
        await _backend.unregister(handle);
      } catch (_) {
        throw const NearbyPlatformException('lan_unavailable');
      }
      throw const NearbyPlatformException('cancelled');
    }
    _handle = handle;
  }

  Future<void> stop() async {
    _wantStarted = false;
    _generation++;
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      try {
        await _backend.unregister(handle);
      } catch (error) {
        throw _platformError(error);
      }
    }
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } on NearbyPlatformException catch (error) {
        if (error.code != 'cancelled') rethrow;
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
  }
}

NearbyAdvertisement? _parseAdvertisement(NearbyMdnsRecord record) {
  try {
    if (record.type != nearbyMdnsServiceType ||
        record.port == null ||
        record.port! < 1 ||
        record.port! > 65535) {
      return null;
    }
    final version = _txt(record.txt, 'v', maxBytes: 4);
    final desktopId = _txt(record.txt, 'id', maxBytes: 32);
    final pairing = _txt(record.txt, 'pairing', maxBytes: 1);
    final name = _txt(record.txt, 'name', maxBytes: 63);
    if (version != nearbyMdnsProtocolVersion ||
        (pairing != '0' && pairing != '1')) {
      return null;
    }
    decodeBytes(desktopId, 16);
    _validateDisplayName(name);
    final addresses = record.addressHints
        .where((address) => address.length <= 64)
        .take(8)
        .toList(growable: false);
    final host = record.host;
    return NearbyAdvertisement(
      desktopId: desktopId,
      displayName: name,
      pairingOpen: pairing == '1',
      port: record.port!,
      addressHints: addresses,
      hostHint: host != null && host.length <= 255 ? host : null,
    );
  } catch (_) {
    return null;
  }
}

String _txt(Map<String, List<int>?> txt, String key, {required int maxBytes}) {
  final bytes = txt[key];
  if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
    throw const FormatException();
  }
  return utf8.decode(bytes, allowMalformed: false);
}

void _validateDisplayName(String name) {
  try {
    validateName(name);
  } catch (_) {
    throw const NearbyPlatformException('invalid_argument');
  }
  if (utf8.encode(name).length > 63) {
    throw const NearbyPlatformException('invalid_argument');
  }
}

NearbyPlatformException _platformError(Object error) {
  if (error is NearbyPlatformException) return error;
  if (error is nsd.NsdError && error.cause == nsd.ErrorCause.securityIssue) {
    return const NearbyPlatformException('permission_denied');
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        code.contains('security')) {
      return const NearbyPlatformException('permission_denied');
    }
  }
  return const NearbyPlatformException('lan_unavailable');
}
