import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

const _documentVersion = 1;
const _maximumClientCredentials = 64;

/// Minimal protected key-value boundary used by the one-document store.
/// Production callers should use [FlutterSecureValueStore].
abstract interface class ProtectedValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class FlutterSecureValueStore implements ProtectedValueStore {
  const FlutterSecureValueStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Public error codes contain no storage contents or platform exception text.
final class NearbyStorageException implements Exception {
  const NearbyStorageException(this.code);

  final String code;

  @override
  String toString() => 'NearbyStorageException($code)';
}

final class PairedDeviceMetadata {
  const PairedDeviceMetadata({
    required this.tokenId,
    required this.clientId,
    required this.clientName,
    required this.lastUsedAt,
  });

  final String tokenId;
  final String clientId;
  final String clientName;
  final DateTime lastUsedAt;
}

final class PersistedDesktopIdentity {
  const PersistedDesktopIdentity({
    required this.desktopId,
    required this.tlsIdentity,
  });

  final String desktopId;
  final TlsIdentity tlsIdentity;

  @override
  String toString() => 'PersistedDesktopIdentity([REDACTED])';
}

/// A single protected JSON document for one isolated MeowWatch data profile.
///
/// [namespaceHash] is the lowercase SHA-256 hex digest of the caller's
/// resolved `MEOWWATCH_DATA_DIR` namespace. The source path is never stored.
/// All mutations for the namespace in the current isolate are serialized and
/// replace the document in one protected-storage write.
final class ProtectedNearbyStore implements NearbySecretStore {
  factory ProtectedNearbyStore({
    required String namespaceHash,
    ProtectedValueStore protectedValues = const FlutterSecureValueStore(),
  }) => ProtectedNearbyStore._(protectedValues, _storageKey(namespaceHash));

  ProtectedNearbyStore._(this._protectedValues, this._key);

  final ProtectedValueStore _protectedValues;
  final String _key;
  static final Map<String, Future<void>> _tails = {};

  static String _storageKey(String hash) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw ArgumentError.value(
        hash,
        'namespaceHash',
        'must be a lowercase SHA-256 hex digest',
      );
    }
    return 'meowwatch.nearby.v1.$hash';
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final previous = _tails[_key] ?? Future<void>.value();
    late final Future<void> tail;
    tail = previous.then((_) async {
      try {
        result.complete(await operation());
      } on NearbyStorageException catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } catch (error, stackTrace) {
        result.completeError(
          const NearbyStorageException('storage_unavailable'),
          stackTrace,
        );
      }
    });
    _tails[_key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[_key], tail)) _tails.remove(_key);
      }),
    );
    return result.future;
  }

  Future<_Document> _load() async {
    final encoded = await _protectedValues.read(_key);
    if (encoded == null) return _Document.empty();
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?>) throw const FormatException();
      return _Document.fromJson(value);
    } catch (_) {
      throw const NearbyStorageException('storage_corrupt');
    }
  }

  Future<void> _save(_Document document) =>
      _protectedValues.write(_key, jsonEncode(document.toJson()));

  @override
  Future<DeviceCredential?> read(String tokenId) => _serialized(() async {
    try {
      decodeBytes(tokenId, 16);
    } catch (_) {
      throw const NearbyStorageException('storage_invalid_argument');
    }
    final document = await _load();
    if (document.revokedTokenIds.contains(tokenId)) return null;
    return document.desktopCredentials[tokenId];
  });

  @override
  Future<void> write(DeviceCredential credential) => _serialized(() async {
    final document = await _load();
    if (document.revokedTokenIds.contains(credential.tokenId)) {
      throw const NearbyStorageException('credential_revoked');
    }
    document.desktopCredentials[credential.tokenId] = credential;
    await _save(document);
  });

  @override
  Future<void> revoke(String tokenId) => _serialized(() async {
    try {
      decodeBytes(tokenId, 16);
    } catch (_) {
      throw const NearbyStorageException('storage_invalid_argument');
    }
    final document = await _load();
    document.desktopCredentials.remove(tokenId);
    document.revokedTokenIds.add(tokenId);
    await _save(document);
  });

  Future<List<PairedDeviceMetadata>> listPairedDevices() =>
      _serialized(() async {
        final document = await _load();
        final devices = document.desktopCredentials.values
            .where(
              (credential) =>
                  !document.revokedTokenIds.contains(credential.tokenId),
            )
            .map(
              (credential) => PairedDeviceMetadata(
                tokenId: credential.tokenId,
                clientId: credential.clientId,
                clientName: credential.clientName,
                lastUsedAt: credential.lastUsedAt,
              ),
            )
            .toList();
        devices.sort((a, b) {
          final recent = b.lastUsedAt.compareTo(a.lastUsedAt);
          return recent != 0 ? recent : a.tokenId.compareTo(b.tokenId);
        });
        return List.unmodifiable(devices);
      });

  Future<PersistedDesktopIdentity> loadOrCreateDesktopIdentity({
    required Future<TlsIdentity> Function() createTlsIdentity,
    SecureRandom? random,
  }) => _serialized(() async {
    final document = await _load();
    final existing = document.identity;
    if (existing != null) return existing;
    final identity = PersistedDesktopIdentity(
      desktopId: encodeBytes((random ?? SystemSecureRandom()).bytes(16)),
      tlsIdentity: await createTlsIdentity(),
    );
    _validateIdentity(identity);
    document.identity = identity;
    await _save(document);
    return identity;
  });

  Future<NearbyClientCredential?> readClient(String desktopId) =>
      _serialized(() async {
        try {
          decodeBytes(desktopId, 16);
        } catch (_) {
          throw const NearbyStorageException('storage_invalid_argument');
        }
        return (await _load()).clientCredentials[desktopId];
      });

  Future<void> _writeClient(NearbyClientCredential credential) =>
      _serialized(() async {
        final document = await _load();
        if (!document.clientCredentials.containsKey(credential.desktopId) &&
            document.clientCredentials.length >= _maximumClientCredentials) {
          throw const NearbyStorageException('storage_limit');
        }
        document.clientCredentials[credential.desktopId] = credential;
        await _save(document);
      });

  /// Returns a bounded snapshot for paired-desktop fallback when discovery is
  /// unavailable. Credential objects redact [toString]; UI must render only
  /// non-secret fields and retrieve by desktop ID through [clientStore].
  Future<List<NearbyClientCredential>> listClientCredentials() =>
      _serialized(() async {
        final credentials = (await _load()).clientCredentials.values.toList()
          ..sort((a, b) => a.desktopId.compareTo(b.desktopId));
        if (credentials.length > _maximumClientCredentials) {
          throw const NearbyStorageException('storage_corrupt');
        }
        return List.unmodifiable(credentials);
      });

  Future<void> remove(String desktopId) => _serialized(() async {
    try {
      decodeBytes(desktopId, 16);
    } catch (_) {
      throw const NearbyStorageException('storage_invalid_argument');
    }
    final document = await _load();
    document.clientCredentials.remove(desktopId);
    await _save(document);
  });

  // NearbySecretStore and NearbyClientStore both use `read(String)`. Since the
  // two meanings cannot be disambiguated at runtime, expose a typed client view.
  NearbyClientStore get clientStore => _ClientStoreView(this);
}

final class _ClientStoreView implements NearbyClientStore {
  const _ClientStoreView(this._store);
  final ProtectedNearbyStore _store;

  @override
  Future<NearbyClientCredential?> read(String desktopId) =>
      _store.readClient(desktopId);

  @override
  Future<void> remove(String desktopId) => _store.remove(desktopId);

  @override
  Future<void> write(NearbyClientCredential credential) =>
      _store._writeClient(credential);
}

final class _Document {
  _Document({
    required this.identity,
    required this.desktopCredentials,
    required this.revokedTokenIds,
    required this.clientCredentials,
  });

  factory _Document.empty() => _Document(
    identity: null,
    desktopCredentials: {},
    revokedTokenIds: {},
    clientCredentials: {},
  );

  factory _Document.fromJson(Map<String, Object?> json) {
    if (json['v'] != _documentVersion) throw const FormatException();
    final identityJson = json['identity'];
    final desktopJson = _map(json['desktopCredentials']);
    final clientJson = _map(json['clientCredentials']);
    final revokedJson = json['revokedTokenIds'];
    if (revokedJson is! List<Object?>) throw const FormatException();

    final desktopCredentials = <String, DeviceCredential>{};
    for (final entry in desktopJson.entries) {
      final credential = _deviceCredential(_map(entry.value));
      if (credential.tokenId != entry.key ||
          desktopCredentials.putIfAbsent(entry.key, () => credential) !=
              credential) {
        throw const FormatException();
      }
    }
    final revoked = <String>{};
    for (final value in revokedJson) {
      if (value is! String || !revoked.add(value)) {
        throw const FormatException();
      }
      decodeBytes(value, 16);
    }
    if (desktopCredentials.keys.any(revoked.contains)) {
      throw const FormatException();
    }
    final clientCredentials = <String, NearbyClientCredential>{};
    for (final entry in clientJson.entries) {
      final credential = _clientCredential(_map(entry.value));
      if (credential.desktopId != entry.key ||
          clientCredentials.putIfAbsent(entry.key, () => credential) !=
              credential) {
        throw const FormatException();
      }
    }
    if (clientCredentials.length > _maximumClientCredentials) {
      throw const FormatException();
    }
    final identity = identityJson == null
        ? null
        : _desktopIdentity(_map(identityJson));
    return _Document(
      identity: identity,
      desktopCredentials: desktopCredentials,
      revokedTokenIds: revoked,
      clientCredentials: clientCredentials,
    );
  }

  PersistedDesktopIdentity? identity;
  final Map<String, DeviceCredential> desktopCredentials;
  final Set<String> revokedTokenIds;
  final Map<String, NearbyClientCredential> clientCredentials;

  Map<String, Object?> toJson() => {
    'v': _documentVersion,
    'identity': identity == null ? null : _identityJson(identity!),
    'desktopCredentials': {
      for (final entry in desktopCredentials.entries)
        entry.key: _deviceCredentialJson(entry.value),
    },
    'revokedTokenIds': revokedTokenIds.toList()..sort(),
    'clientCredentials': {
      for (final entry in clientCredentials.entries)
        entry.key: _clientCredentialJson(entry.value),
    },
  };
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) throw const FormatException();
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw const FormatException();
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw const FormatException();
  return value;
}

DeviceCredential _deviceCredential(Map<String, Object?> json) =>
    DeviceCredential(
      tokenId: _string(json, 'tokenId'),
      clientId: _string(json, 'clientId'),
      clientName: _string(json, 'clientName'),
      secret: decodeBytes(_string(json, 'secret'), 32),
      lastUsedAt: DateTime.parse(_string(json, 'lastUsedAt')).toUtc(),
    );

Map<String, Object?> _deviceCredentialJson(DeviceCredential credential) => {
  'tokenId': credential.tokenId,
  'clientId': credential.clientId,
  'clientName': credential.clientName,
  'secret': encodeBytes(credential.secret),
  'lastUsedAt': credential.lastUsedAt.toUtc().toIso8601String(),
};

NearbyClientCredential _clientCredential(Map<String, Object?> json) =>
    NearbyClientCredential(
      desktopId: _string(json, 'desktopId'),
      tokenId: _string(json, 'tokenId'),
      clientId: _string(json, 'clientId'),
      clientName: _string(json, 'clientName'),
      endpoint: LanEndpoint(
        address: LanIpv4Address.parse(_string(json, 'address')),
        port: _integer(json, 'port'),
      ),
      certificateSha256: decodeBytes(_string(json, 'certificateSha256'), 32),
      secret: decodeBytes(_string(json, 'secret'), 32),
    );

Map<String, Object?> _clientCredentialJson(NearbyClientCredential credential) =>
    {
      'desktopId': credential.desktopId,
      'tokenId': credential.tokenId,
      'clientId': credential.clientId,
      'clientName': credential.clientName,
      'address': credential.endpoint.address.toString(),
      'port': credential.endpoint.port,
      'certificateSha256': encodeBytes(credential.certificateSha256),
      'secret': encodeBytes(credential.secret),
    };

PersistedDesktopIdentity _desktopIdentity(Map<String, Object?> json) {
  final identity = PersistedDesktopIdentity(
    desktopId: _string(json, 'desktopId'),
    tlsIdentity: TlsIdentity(
      certificatePem: _string(json, 'certificatePem'),
      privateKeyPem: _string(json, 'privateKeyPem'),
    ),
  );
  _validateIdentity(identity);
  return identity;
}

Map<String, Object?> _identityJson(PersistedDesktopIdentity identity) => {
  'desktopId': identity.desktopId,
  'certificatePem': identity.tlsIdentity.certificatePem,
  'privateKeyPem': identity.tlsIdentity.privateKeyPem,
};

void _validateIdentity(PersistedDesktopIdentity identity) {
  decodeBytes(identity.desktopId, 16);
  if (identity.tlsIdentity.certificatePem.isEmpty ||
      identity.tlsIdentity.privateKeyPem.isEmpty) {
    throw const FormatException();
  }
  identity.tlsIdentity.certificateSha256;
  identity.tlsIdentity.createServerContext();
}
