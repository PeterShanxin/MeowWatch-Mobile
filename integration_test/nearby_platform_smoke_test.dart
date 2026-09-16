import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/core/nearby/android_lan.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _markerKey = 'meowwatch.nearby.runtime.stage.v1';
const _namespaceA = 'nearby-runtime/profile-a';
const _namespaceB = 'nearby-runtime/profile-b';
const _testDisplayName = 'MeowWatch runtime probe';
const _testPort = 54321;
const _pluginTimeout = Duration(seconds: 20);
const _identityTimeout = Duration(seconds: 90);
const _discoveryWindow = Duration(seconds: 5);

final _tokenLive = encodeBytes(List<int>.filled(16, 0x11));
final _tokenRevoked = encodeBytes(List<int>.filled(16, 0x12));
final _tokenB = encodeBytes(List<int>.filled(16, 0x13));
final _clientA = encodeBytes(List<int>.filled(16, 0x21));
final _clientB = encodeBytes(List<int>.filled(16, 0x22));
final _desktopA = encodeBytes(List<int>.filled(16, 0x31));
final _mdnsDesktop = encodeBytes(List<int>.filled(16, 0x41));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Android Nearby platform state survives process restarts',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This gate verifies production Android plugins.',
      );
      await tester.pumpWidget(const _RuntimeSurface());

      final preferences = await SharedPreferences.getInstance();
      final marker = _readMarker(preferences.getString(_markerKey));
      final stage = marker == null ? 1 : (marker['stage']! as int) + 1;
      expect(stage, inInclusiveRange(1, 3));

      final storeA = ProtectedNearbyStore(
        namespaceHash: sha256.convert(utf8.encode(_namespaceA)).toString(),
      );
      final storeB = ProtectedNearbyStore(
        namespaceHash: sha256.convert(utf8.encode(_namespaceB)).toString(),
      );
      final evidence = <String, Object?>{
        'stage': stage,
        'platform': Platform.operatingSystem,
        'protectedProvider': 'FlutterSecureStorage',
        'namespacePathsStored': false,
        'rawSecretsReported': false,
      };

      switch (stage) {
        case 1:
          await _bootstrap(preferences, storeA, storeB, evidence);
          evidence['lan'] = await _verifyAndroidLan();
          evidence['mdns'] = await _verifyMdnsLifecycle();
        case 2:
          await _verifyAndRevoke(
            preferences,
            marker!,
            storeA,
            storeB,
            evidence,
          );
        case 3:
          await _verifyFinal(preferences, marker!, storeA, storeB, evidence);
      }

      evidence['completed'] = true;
      binding.reportData = <String, Object?>{'nearbyRuntime': evidence};
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _bootstrap(
  SharedPreferences preferences,
  ProtectedNearbyStore storeA,
  ProtectedNearbyStore storeB,
  Map<String, Object?> evidence,
) async {
  final identity = await storeA
      .loadOrCreateDesktopIdentity(createTlsIdentity: TlsIdentity.generate)
      .timeout(_identityTimeout);
  final live = _credential(_tokenLive, _clientA, 'Runtime phone A', 0x51);
  final revoked = _credential(
    _tokenRevoked,
    _clientA,
    'Runtime revoked phone',
    0x52,
  );
  final isolated = _credential(_tokenB, _clientB, 'Runtime phone B', 0x53);
  await storeA.write(live).timeout(_pluginTimeout);
  await storeA.write(revoked).timeout(_pluginTimeout);
  await storeA.revoke(_tokenRevoked).timeout(_pluginTimeout);
  await storeA.clientStore.write(_clientCredential()).timeout(_pluginTimeout);
  await storeB.write(isolated).timeout(_pluginTimeout);

  expect(await storeA.read(_tokenLive), isNotNull);
  expect(await storeA.read(_tokenRevoked), isNull);
  expect(await storeA.read(_tokenB), isNull);
  expect(await storeB.read(_tokenLive), isNull);
  expect(await storeB.read(_tokenB), isNotNull);
  expect(await storeB.clientStore.read(_desktopA), isNull);

  final marker = <String, Object?>{
    'v': 1,
    'stage': 1,
    // Only a one-way comparison digest crosses process boundaries. The
    // protected private key, credentials and token IDs never enter this marker.
    'identityDigest': _identityDigest(identity),
  };
  expect(await preferences.setString(_markerKey, jsonEncode(marker)), isTrue);
  evidence.addAll(<String, Object?>{
    'identityCreated': true,
    'desktopCredentialWritten': true,
    'clientCredentialWritten': true,
    'revocationTombstoneWritten': true,
    'namespaceIsolationVerified': true,
  });
}

Future<void> _verifyAndRevoke(
  SharedPreferences preferences,
  Map<String, Object?> marker,
  ProtectedNearbyStore storeA,
  ProtectedNearbyStore storeB,
  Map<String, Object?> evidence,
) async {
  expect(marker['stage'], 1);
  final identity = await storeA
      .loadOrCreateDesktopIdentity(createTlsIdentity: _unexpectedIdentity)
      .timeout(_pluginTimeout);
  expect(_identityDigest(identity), marker['identityDigest']);

  final live = await storeA.read(_tokenLive).timeout(_pluginTimeout);
  expect(live, isNotNull);
  expect(constantTimeEqual(live!.secret, List<int>.filled(32, 0x51)), isTrue);
  expect(await storeA.read(_tokenRevoked), isNull);
  await _expectRevokedWrite(storeA, _tokenRevoked, 0x52);
  final client = await storeA.clientStore
      .read(_desktopA)
      .timeout(_pluginTimeout);
  expect(client, isNotNull);
  expect(constantTimeEqual(client!.secret, List<int>.filled(32, 0x61)), isTrue);
  expect(await storeB.read(_tokenLive), isNull);
  expect(await storeB.read(_tokenB), isNotNull);
  expect(await storeB.clientStore.read(_desktopA), isNull);

  await storeA.revoke(_tokenLive).timeout(_pluginTimeout);
  await storeA.clientStore.remove(_desktopA).timeout(_pluginTimeout);
  final next = <String, Object?>{...marker, 'stage': 2};
  expect(await preferences.setString(_markerKey, jsonEncode(next)), isTrue);
  evidence.addAll(<String, Object?>{
    'identityRestoredAfterRestart': true,
    'identityKeyContinuityVerified': true,
    'desktopCredentialRestoredAfterRestart': true,
    'clientCredentialRestoredAfterRestart': true,
    'earlierRevocationSurvivedRestart': true,
    'namespaceIsolationVerified': true,
    'finalRevocationWritten': true,
    'clientCredentialRemoved': true,
  });
}

Future<void> _verifyFinal(
  SharedPreferences preferences,
  Map<String, Object?> marker,
  ProtectedNearbyStore storeA,
  ProtectedNearbyStore storeB,
  Map<String, Object?> evidence,
) async {
  expect(marker['stage'], 2);
  final identity = await storeA
      .loadOrCreateDesktopIdentity(createTlsIdentity: _unexpectedIdentity)
      .timeout(_pluginTimeout);
  expect(_identityDigest(identity), marker['identityDigest']);
  expect(await storeA.read(_tokenLive), isNull);
  expect(await storeA.read(_tokenRevoked), isNull);
  await _expectRevokedWrite(storeA, _tokenLive, 0x51);
  await _expectRevokedWrite(storeA, _tokenRevoked, 0x52);
  expect(await storeA.clientStore.read(_desktopA), isNull);
  expect(await storeB.read(_tokenB), isNotNull);
  expect(await storeB.read(_tokenLive), isNull);
  expect(await storeB.clientStore.read(_desktopA), isNull);
  expect(await storeA.listPairedDevices(), isEmpty);
  expect(
    await preferences.setString(
      _markerKey,
      jsonEncode(<String, Object?>{...marker, 'stage': 3}),
    ),
    isTrue,
  );
  evidence.addAll(<String, Object?>{
    'identityRestoredAfterSecondRestart': true,
    'identityKeyContinuityVerified': true,
    'revocationSurvivedSecondRestart': true,
    'revokedCredentialCannotBeRewritten': true,
    'clientRemovalSurvivedRestart': true,
    'otherNamespaceCredentialUnaffected': true,
    'namespaceIsolationVerified': true,
  });
}

Future<Map<String, Object?>> _verifyAndroidLan() async {
  final interfaces = await AndroidLan().list().timeout(_pluginTimeout);
  expect(interfaces, isNotEmpty);
  for (final interface in interfaces) {
    expect(interface.id, isNotEmpty);
    expect(interface.name, anyOf('Wi-Fi', 'Ethernet'));
    expect(interface.subnet.prefixLength, inInclusiveRange(1, 30));
    expect(interface.subnet.contains(interface.subnet.localAddress), isTrue);
  }
  return <String, Object?>{
    'nativeChannelReturned': true,
    'nativePrivateRouteGuardAccepted': true,
    'interfaceCount': interfaces.length,
    'friendlyNames': interfaces.map((entry) => entry.name).toSet().toList(),
    'prefixLengths': interfaces
        .map((entry) => entry.subnet.prefixLength)
        .toSet()
        .toList(),
    'addressesReported': false,
  };
}

Future<Map<String, Object?>> _verifyMdnsLifecycle() async {
  final discovery = NearbyDiscovery();
  final registration = NearbyAdvertisementRegistration(
    desktopId: _mdnsDesktop,
    displayName: _testDisplayName,
    port: _testPort,
    pairingOpen: true,
  );
  final observed = <String, Map<String, Object?>>{};
  final subscription = discovery.events.listen((event) {
    final advertisement = event.advertisement;
    final key = '${advertisement.displayName}:${advertisement.port}';
    observed[key] = <String, Object?>{
      'name': advertisement.displayName,
      'port': advertisement.port,
      'pairingOpen': advertisement.pairingOpen,
      'addressHintCount': advertisement.addressHints.length,
      'hostHintPresent': advertisement.hostHint != null,
      'status': event.status.name,
    };
  });
  try {
    await discovery.start().timeout(_pluginTimeout);
    expect(discovery.isRunning, isTrue);
    await registration.start().timeout(_pluginTimeout);
    expect(registration.isRunning, isTrue);
    await Future<void>.delayed(_discoveryWindow);
    await registration.stop().timeout(_pluginTimeout);
    expect(registration.isRunning, isFalse);
    await discovery.stop().timeout(_pluginTimeout);
    expect(discovery.isRunning, isFalse);
  } on NearbyPlatformException catch (error) {
    fail('NSD lifecycle failed with public code ${error.code}.');
  } finally {
    await registration.dispose();
    await discovery.dispose();
    await subscription.cancel();
  }
  return <String, Object?>{
    'realPluginStartStopCompleted': true,
    'localTestAdvertisementObserved': observed.containsKey(
      '$_testDisplayName:$_testPort',
    ),
    'observedAdvertisementCount': observed.length,
    'observedAdvertisementMetadata': observed.values.toList(),
    'rawAddressesReported': false,
    'windowsDesktopDiscoveryClaimed': false,
  };
}

DeviceCredential _credential(
  String tokenId,
  String clientId,
  String name,
  int secretByte,
) => DeviceCredential(
  tokenId: tokenId,
  clientId: clientId,
  clientName: name,
  secret: List<int>.filled(32, secretByte),
  lastUsedAt: DateTime.utc(2026, 9, 16, 12),
);

NearbyClientCredential _clientCredential() => NearbyClientCredential(
  desktopId: _desktopA,
  tokenId: encodeBytes(List<int>.filled(16, 0x32)),
  clientId: _clientA,
  clientName: 'Runtime mobile client',
  endpoint: LanEndpoint(
    address: LanIpv4Address.parse('10.0.2.2'),
    port: _testPort,
  ),
  certificateSha256: List<int>.filled(32, 0x62),
  secret: List<int>.filled(32, 0x61),
);

Future<TlsIdentity> _unexpectedIdentity() => Future<TlsIdentity>.error(
  TestFailure('Protected identity was regenerated after process restart.'),
);

String _identityDigest(PersistedDesktopIdentity identity) => sha256
    .convert(
      utf8.encode(
        '${identity.desktopId}\u0000'
        '${identity.tlsIdentity.certificatePem}\u0000'
        '${identity.tlsIdentity.privateKeyPem}',
      ),
    )
    .toString();

Future<void> _expectRevokedWrite(
  ProtectedNearbyStore store,
  String tokenId,
  int secretByte,
) async {
  try {
    await store
        .write(
          _credential(tokenId, _clientA, 'Revoked runtime phone', secretByte),
        )
        .timeout(_pluginTimeout);
    fail('A revoked credential was accepted after process restart.');
  } on NearbyStorageException catch (error) {
    expect(error.code, 'credential_revoked');
  }
}

Map<String, Object?>? _readMarker(String? encoded) {
  if (encoded == null) return null;
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, Object?> ||
      decoded['v'] != 1 ||
      decoded['stage'] is! int ||
      decoded['identityDigest'] is! String) {
    throw TestFailure('Nearby runtime stage marker is malformed.');
  }
  return decoded;
}

class _RuntimeSurface extends StatelessWidget {
  const _RuntimeSurface();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(child: Text('Verifying protected Nearby platform state…')),
    ),
  );
}
