import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';

void main() {
  const namespaceA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const namespaceB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('serializes concurrent writes into one protected document', () async {
    final backend = _MemoryProtectedStore(
      writeDelay: const Duration(milliseconds: 5),
    );
    final firstStore = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: backend,
    );
    final secondStore = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: backend,
    );
    final first = _device(1, 'First phone');
    final second = _device(2, 'Second phone');

    await Future.wait([firstStore.write(first), secondStore.write(second)]);

    expect((await firstStore.read(first.tokenId))?.clientName, 'First phone');
    expect(
      (await secondStore.read(second.tokenId))?.clientName,
      'Second phone',
    );
    expect(backend.maximumConcurrentWrites, 1);
    expect(backend.values, hasLength(1));
  });

  test(
    'revocation is durable and cannot be resurrected by a queued write',
    () async {
      final backend = _MemoryProtectedStore();
      final store = ProtectedNearbyStore(
        namespaceHash: namespaceA,
        protectedValues: backend,
      );
      final credential = _device(3, 'Revoked phone');
      await store.write(credential);

      final revoke = store.revoke(credential.tokenId);
      final rewrite = store.write(credential);
      await revoke;
      await expectLater(
        rewrite,
        throwsA(
          isA<NearbyStorageException>().having(
            (error) => error.code,
            'code',
            'credential_revoked',
          ),
        ),
      );

      final afterRestart = ProtectedNearbyStore(
        namespaceHash: namespaceA,
        protectedValues: backend,
      );
      expect(await afterRestart.read(credential.tokenId), isNull);
      expect(await afterRestart.listPairedDevices(), isEmpty);
    },
  );

  test('fails closed for a corrupt protected document', () async {
    final backend = _MemoryProtectedStore(readValue: '{broken');
    final store = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: backend,
    );

    await expectLater(
      store.listPairedDevices(),
      throwsA(
        isA<NearbyStorageException>().having(
          (error) => error.code,
          'code',
          'storage_corrupt',
        ),
      ),
    );
    await expectLater(
      store.write(_device(4, 'Blocked phone')),
      throwsA(isA<NearbyStorageException>()),
    );
    expect(backend.writeCount, 0);
  });

  test('isolates documents by caller supplied namespace hash', () async {
    final backend = _MemoryProtectedStore();
    final first = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: backend,
    );
    final second = ProtectedNearbyStore(
      namespaceHash: namespaceB,
      protectedValues: backend,
    );
    final credential = _device(5, 'Profile A');

    await first.write(credential);
    final secondCredential = _device(6, 'Profile B');
    await second.write(secondCredential);

    expect(await first.read(credential.tokenId), isNotNull);
    expect(await second.read(credential.tokenId), isNull);
    expect(await first.read(secondCredential.tokenId), isNull);
    expect(await second.read(secondCredential.tokenId), isNotNull);
    expect(backend.values, hasLength(2));
    expect(backend.values.keys, everyElement(isNot(contains(r'\'))));
  });

  test('persists one TLS identity across concurrent callers', () async {
    final backend = _MemoryProtectedStore();
    final store = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: backend,
    );
    var generated = 0;
    final identity = await TlsIdentity.generate();
    Future<TlsIdentity> generate() async {
      generated++;
      return identity;
    }

    final results = await Future.wait([
      store.loadOrCreateDesktopIdentity(
        createTlsIdentity: generate,
        random: _FixedRandom(7),
      ),
      store.loadOrCreateDesktopIdentity(
        createTlsIdentity: generate,
        random: _FixedRandom(8),
      ),
    ]);

    expect(generated, 1);
    expect(results[0].desktopId, results[1].desktopId);
    expect(
      results[0].tlsIdentity.certificateSha256,
      results[1].tlsIdentity.certificateSha256,
    );
  });

  test(
    'phone credentials use the same serialized protected document',
    () async {
      final backend = _MemoryProtectedStore();
      final store = ProtectedNearbyStore(
        namespaceHash: namespaceA,
        protectedValues: backend,
      );
      final clientStore = store.clientStore;
      final credential = NearbyClientCredential(
        desktopId: _id(9),
        tokenId: _id(10),
        clientId: _id(11),
        clientName: 'My phone',
        endpoint: LanEndpoint(
          address: LanIpv4Address.parse('192.168.1.4'),
          port: 43123,
        ),
        certificateSha256: List.filled(32, 12),
        secret: List.filled(32, 13),
      );

      await Future.wait([
        store.write(_device(14, 'Desktop peer')),
        clientStore.write(credential),
      ]);

      final restored = await clientStore.read(credential.desktopId);
      expect(restored?.tokenId, credential.tokenId);
      expect(restored?.endpoint.address.toString(), '192.168.1.4');
      expect(
        (await store.listClientCredentials()).map((item) => item.desktopId),
        [credential.desktopId],
      );
      expect(await store.listPairedDevices(), hasLength(1));
      await clientStore.remove(credential.desktopId);
      expect(await clientStore.read(credential.desktopId), isNull);
    },
  );

  test('paired desktop fallback is bounded to 64 credentials', () async {
    final store = ProtectedNearbyStore(
      namespaceHash: namespaceA,
      protectedValues: _MemoryProtectedStore(),
    );
    for (var byte = 1; byte <= 64; byte++) {
      await store.clientStore.write(_client(byte));
    }

    expect(await store.listClientCredentials(), hasLength(64));
    await expectLater(
      store.clientStore.write(_client(65)),
      throwsA(
        isA<NearbyStorageException>().having(
          (error) => error.code,
          'code',
          'storage_limit',
        ),
      ),
    );
  });

  test('rejects a raw or malformed namespace instead of storing its path', () {
    expect(
      () => ProtectedNearbyStore(namespaceHash: r'C:\Users\me\profile'),
      throwsArgumentError,
    );
    expect(
      () => ProtectedNearbyStore(namespaceHash: namespaceA.toUpperCase()),
      throwsArgumentError,
    );
  });
}

DeviceCredential _device(int byte, String name) => DeviceCredential(
  tokenId: _id(byte),
  clientId: _id(byte + 32),
  clientName: name,
  secret: List.filled(32, byte),
  lastUsedAt: DateTime.utc(2026, 9, byte.clamp(1, 28)),
);

String _id(int byte) => encodeBytes(List.filled(16, byte));

NearbyClientCredential _client(int byte) => NearbyClientCredential(
  desktopId: _id(byte),
  tokenId: _id((byte + 64) % 256),
  clientId: _id((byte + 128) % 256),
  clientName: 'Phone $byte',
  endpoint: LanEndpoint(
    address: LanIpv4Address.parse('192.168.1.${byte + 1}'),
    port: 43000 + byte,
  ),
  certificateSha256: List.filled(32, byte),
  secret: List.filled(32, (byte + 1) % 256),
);

final class _FixedRandom implements SecureRandom {
  const _FixedRandom(this.byte);
  final int byte;
  @override
  Uint8List bytes(int length) => Uint8List.fromList(List.filled(length, byte));
}

final class _MemoryProtectedStore implements ProtectedValueStore {
  _MemoryProtectedStore({this.readValue, this.writeDelay = Duration.zero});

  final String? readValue;
  final Duration writeDelay;
  final Map<String, String> values = {};
  int writeCount = 0;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;

  @override
  Future<String?> read(String key) async => readValue ?? values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    _activeWrites++;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }
    await Future<void>.delayed(writeDelay);
    values[key] = value;
    _activeWrites--;
  }
}
