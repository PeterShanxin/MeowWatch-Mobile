import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Purchases, PurchasesErrorCode;
import 'package:video_player/video_player.dart';

const _apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
const _server = String.fromEnvironment(
  'SYNCPLAY_SERVER',
  defaultValue: 'syncplay.pl',
);
const _port = int.fromEnvironment('SYNCPLAY_PORT', defaultValue: 8995);
const _video = String.fromEnvironment(
  'HOSTING_VIDEO_URL',
  defaultValue:
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
);
const _plus = 'meowwatch_plus';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real TLS playback consumes one host; Test Store unlocks more hosts',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(
        _apiKey.startsWith('test_'),
        isTrue,
        reason: 'REVENUECAT_API_KEY must be a public Test Store key.',
      );
      final started = DateTime.now();
      final runId = 'hosting-${started.microsecondsSinceEpoch}';
      final support = await getApplicationSupportDirectory();
      // Isolated test files, written only by the production repository/policy.
      // No preloaded allowance, fake clock, fabricated receipt, or SDK identity.
      final root = Directory('${support.path}/$runId');
      await root.create();
      final hosts = <_Host>[];
      final peers = <_Peer>[];
      addTearDown(() async {
        for (final peer in peers.reversed) {
          await peer.close();
        }
        for (final host in hosts.reversed) {
          await host.app.close();
        }
      });

      // This harness puts two Android players on one audio-focus manager.
      // Each target below explicitly mixes audio: controller initialization
      // reapplies its options, overwriting an earlier platform-wide setting.
      // Separate phones retain the production target's exclusive-audio policy.

      final verified = <String>[];
      final observations = <Map<String, Object?>>[];
      final screenshots = <String>[];
      final evidence = <String, Object?>{
        'mode': 'hosting_purchase',
        'runtime':
            'Android; two native video targets and two TLS clients in one process',
        'audioFocus':
            'mixWithOthers=true on each target for same-process decoder coexistence',
        'server': '$_server:$_port',
        'video': _video,
        'startedAtUtc': started.toUtc().toIso8601String(),
        'verified': verified,
        'observations': observations,
        'screenshots': screenshots,
      };
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['hostingPurchase'] = evidence;

      final decoderEvidence = <String, Object?>{};
      evidence['decoderCoexistence'] = decoderEvidence;
      await _verifyDecoderCoexistence(tester, decoderEvidence);
      verified.add('two_native_decoders_advance_without_stealing_audio_focus');

      var host = await _Host.open(root);
      hosts.add(host);
      expect(
        host.billing.isPlus,
        isFalse,
        reason:
            'Use a Test Store customer without active Plus for the free-to-paid funnel.',
      );
      expect(host.billing.currentOffering?.identifier, 'default');
      expect(host.monthly.storeProduct.identifier, 'meowwatch_plus_monthly');
      evidence['localizedPrice'] = host.monthly.storeProduct.priceString;
      final customerHash = _customerHash(host.billing);
      evidence['customerHash'] = customerHash;
      verified.add('real_sdk_catalog_initial_free_customer');
      await host.app.setName('HostingPhone');
      final first = _ticket('$runId-free', host.app.username);
      expect(await host.quota.remainingFreeHostsToday(), 1);
      expect(await host.app.connect(first), isTrue, reason: host.app.message);
      expect(host.app.peers, isEmpty);
      await host.app.load(MediaItem.fromUrl(_video));
      _expectMedia(host.target);
      await binding.convertFlutterSurfaceToImage();

      _Peer? peer;
      Future<void> capture(String name) async {
        await tester.pumpWidget(
          _RuntimeView(host: host, peer: peer, stage: name),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await binding.takeScreenshot(name);
        screenshots.add(name);
        observations.add({
          'stage': name,
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'remainingFreeHosts': await host.quota.remainingFreeHostsToday(),
          'isPlus': host.billing.isPlus,
          'needsPlus': host.app.needsPlus,
          'hostPositionMs': host.target.snapshot.position.inMilliseconds,
          'hostPlaying': host.target.snapshot.playing,
          'peerPositionMs': peer?.target.snapshot.position.inMilliseconds,
          'peerPlaying': peer?.target.snapshot.playing,
          'remotePeers': host.app.peers.length,
        });
      }

      await host.app.togglePlay();
      await _until(
        tester,
        () =>
            host.target.snapshot.playing &&
            host.target.snapshot.position.inMilliseconds >= 600,
        'solo native playback',
        host,
      );
      expect(await host.quota.remainingFreeHostsToday(), 1);
      expect(await host.quotaFile.exists(), isFalse);
      await capture('solo-play-does-not-consume');
      await host.app.togglePlay();
      verified.add('room_creation_and_solo_play_do_not_consume');

      peer = await _Peer.open(first.config, MediaItem.fromUrl(_video));
      peers.add(peer);
      await _until(
        tester,
        () => host.app.peers.contains(peer!.sync.username),
        'actual TLS peer presence',
        host,
      );
      await _until(
        tester,
        () => !peer!.target.snapshot.playing && !host.target.snapshot.playing,
        'both real decoders paused',
        host,
      );
      expect(await host.quota.remainingFreeHostsToday(), 1);
      expect(await host.quotaFile.exists(), isFalse);
      verified.add('peer_join_without_play_does_not_consume');
      await _playTogether(tester, host, peer);
      expect(await host.quota.remainingFreeHostsToday(), 0);
      final firstLedger = await host.quotaFile.readAsString();
      expect(await host.quota.canHostNow(sessionId: first.id), isTrue);
      expect(await host.quota.canHostNow(sessionId: '$runId-new'), isFalse);
      await capture('first-real-together-session');
      await _pauseTogether(tester, host, peer);
      verified.add('actual_peer_and_native_play_consume_one_host');

      final reconnectStates = <String>[];
      final client = host.clients.last;
      final reconnectSubscription = client.connectionState.listen(
        (state) => reconnectStates.add(state.status.name),
      );
      addTearDown(reconnectSubscription.cancel);
      // Tears down a live real socket through the watchdog recovery path.
      // This is not mobile radio loss and does not inject any protocol frame.
      client.debugSimulateConnectionLost();
      await _until(
        tester,
        () =>
            reconnectStates.contains('connected') &&
            reconnectStates.any((state) => state != 'connected') &&
            host.app.isConnected &&
            host.app.peers.contains(peer!.sync.username),
        'real secure socket recovery',
        host,
        seconds: 60,
      );
      await reconnectSubscription.cancel();
      await _playTogether(tester, host, peer);
      expect(await host.quotaFile.readAsString(), firstLedger);
      expect(host.app.room!.id, first.id);
      await capture('reconnect-keeps-free-session');
      await _pauseTogether(tester, host, peer);
      evidence['reconnectStates'] = reconnectStates;
      verified.add('real_socket_reconnect_does_not_consume_again');

      await tester.pumpWidget(const SizedBox.shrink());
      await host.app.close();
      host = await _Host.open(root);
      hosts.add(host);
      expect(_customerHash(host.billing), customerHash);
      expect(host.billing.isPlus, isFalse);
      final saved = host.app.repository.activeRoom;
      expect(saved, isNotNull);
      expect(saved!.id, first.id);
      expect(saved.isHost, isTrue);
      expect(await host.quota.remainingFreeHostsToday(), 0);
      expect(await host.app.connect(saved), isTrue, reason: host.app.message);
      await host.app.load(MediaItem.fromUrl(_video));
      _expectMedia(host.target);
      await _until(
        tester,
        () => host.app.peers.contains(peer!.sync.username),
        'peer after reopening disk-backed services',
        host,
      );
      await _playTogether(tester, host, peer);
      expect(await host.quotaFile.readAsString(), firstLedger);
      await capture('disk-reopen-keeps-free-session');
      await _pauseTogether(tester, host, peer);
      verified.add('same_process_service_reopen_reuses_durable_room_and_quota');

      final next = _ticket('$runId-plus-one', host.app.username);
      expect(await host.app.connect(next), isFalse);
      expect(host.app.needsPlus, isTrue);
      expect(host.app.room!.id, first.id);
      expect(host.app.repository.activeRoom!.id, first.id);
      expect(await host.quotaFile.readAsString(), firstLedger);
      await capture('next-host-requires-plus');
      verified.add('next_host_denied_with_needs_plus_and_room_preserved');

      for (final status in [BillingStatus.cancelled, BillingStatus.failure]) {
        final outcome = status == BillingStatus.cancelled
            ? 'cancel'
            : 'failure';
        final result = await _purchase(tester, host, peer, outcome);
        expect(result.status, status);
        if (status == BillingStatus.failure) {
          expect(
            result.errorCode,
            PurchasesErrorCode.testStoreSimulatedPurchaseError.index.toString(),
          );
        }
        expect(host.billing.isPlus, isFalse);
        expect(host.app.needsPlus, isTrue);
        expect(host.app.room!.id, first.id);
        expect(await host.quotaFile.readAsString(), firstLedger);
        verified.add('native_${outcome}_preserves_room_and_quota');
      }

      final purchased = await _purchase(tester, host, peer, 'success');
      _expectSuccess(purchased, 'native Test Store purchase');
      _expectPlus(host.billing);
      expect(_customerHash(host.billing), customerHash);
      expect(await host.quotaFile.readAsString(), firstLedger);
      expect(await host.quota.canHostNow(sessionId: next.id), isTrue);
      verified.add('real_purchase_activates_plus_and_unlocks_next_host');
      _expectSuccess(
        await host.billing.restore().timeout(const Duration(seconds: 60)),
        'restore',
      );
      _expectPlus(host.billing);
      expect(await host.quotaFile.readAsString(), firstLedger);
      verified.add('real_restore_preserves_entitlement_and_quota');
      host.app.dismissPaywall();

      for (var number = 1; number <= 2; number++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await peer!.close();
        peer = null;
        final ticket = number == 1
            ? next
            : _ticket('$runId-plus-two', host.app.username);
        expect(
          await host.app.connect(ticket),
          isTrue,
          reason: host.app.message,
        );
        expect(host.app.needsPlus, isFalse);
        expect(host.app.room!.id, ticket.id);
        _expectMedia(host.target);
        peer = await _Peer.open(ticket.config, MediaItem.fromUrl(_video));
        peers.add(peer);
        await _until(
          tester,
          () => host.app.peers.contains(peer!.sync.username),
          'peer in paid hosted session $number',
          host,
        );
        await _playTogether(tester, host, peer);
        expect(await host.quota.remainingFreeHostsToday(), 0);
        expect(
          await host.quota.canHostNow(sessionId: '$runId-another'),
          isTrue,
        );
        await capture('plus-host-$number-playing');
        await _pauseTogether(tester, host, peer);
        verified.add('plus_allows_distinct_real_host_$number');
      }

      await Purchases.invalidateCustomerInfoCache();
      _expectSuccess(
        await host.billing.refresh().timeout(const Duration(seconds: 60)),
        'final fresh customer',
      );
      _expectPlus(host.billing);
      final finalLedger = await host.quotaFile.readAsString();
      _expectSuccess(
        await host.billing.restore().timeout(const Duration(seconds: 60)),
        'final restore',
      );
      expect(await host.quotaFile.readAsString(), finalLedger);
      expect(await host.quota.remainingFreeHostsToday(), 0);
      final ended = DateTime.now();
      expect(
        [ended.year, ended.month, ended.day],
        [started.year, started.month, started.day],
        reason:
            'This single-day funnel crossed midnight; rerun without changing the clock.',
      );
      evidence['remainingFreeHosts'] = 0;
      evidence['finalPlus'] = host.billing.isPlus;
      evidence['completedAtUtc'] = ended.toUtc().toIso8601String();
      evidence['result'] = 'passed';
      debugPrint('HOSTING_PURCHASE_RESULT ${jsonEncode(evidence)}');
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

RoomTicket _ticket(String id, String username) => RoomTicket(
  id: id,
  isHost: true,
  config: RoomConfig(
    server: _server,
    port: _port,
    room: id,
    username: username,
  ),
);

String _customerHash(RevenueCatBillingService billing) => sha256
    .convert(utf8.encode(billing.customerInfo!.originalAppUserId))
    .toString();

void _expectSuccess(BillingResult result, String action) => expect(
  result.status,
  BillingStatus.success,
  reason: '$action: ${result.status.name} ${result.errorCode ?? ''}',
);

void _expectPlus(RevenueCatBillingService billing) {
  expect(billing.isPlus, isTrue);
  final entitlement = billing.customerInfo!.entitlements.active[_plus];
  expect(entitlement, isNotNull);
  expect(entitlement!.isSandbox, isTrue);
  expect(entitlement.productIdentifier, 'meowwatch_plus_monthly');
}

void _expectMedia(LocalMobileTarget target) {
  expect(target.snapshot.ready, isTrue, reason: target.snapshot.error);
  expect(target.controller!.value.isInitialized, isTrue);
  expect(target.snapshot.duration, greaterThan(const Duration(seconds: 5)));
  expect(target.controller!.value.size.width, greaterThan(0));
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String stage,
  _Host host, {
  int seconds = 35,
  _Peer? peer,
}) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > Duration(seconds: seconds)) {
      throw TestFailure(
        '$stage timed out: connected=${host.app.isConnected}, '
        'peers=${host.app.peers.length}, playing=${host.target.snapshot.playing}, '
        'buffering=${host.target.snapshot.buffering}, '
        'position=${host.target.snapshot.position}, error=${host.app.message}, '
        'peerPlaying=${peer?.target.snapshot.playing}, '
        'peerBuffering=${peer?.target.snapshot.buffering}, '
        'peerPosition=${peer?.target.snapshot.position}, '
        'peerErrors=${peer?.errors}, '
        'roomPaused=${host.clients.last.lastObservedRoomState?.paused}, '
        'roomSetBy=${host.clients.last.lastObservedRoomState?.setBy}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _playTogether(WidgetTester tester, _Host host, _Peer peer) async {
  if (host.target.snapshot.playing) await host.app.togglePlay();
  await host.app.seek(Duration.zero);
  await _until(
    tester,
    () =>
        !peer.target.snapshot.playing &&
        peer.target.snapshot.position.inMilliseconds < 800,
    'peer accepted start seek',
    host,
    peer: peer,
  );
  await host.app.togglePlay();
  await _until(
    tester,
    () =>
        host.target.snapshot.playing &&
        peer.target.snapshot.playing &&
        host.target.snapshot.position.inMilliseconds >= 800 &&
        peer.target.snapshot.position.inMilliseconds >= 400,
    'both actual native decoders advancing',
    host,
    peer: peer,
  );
  final hostPosition = host.target.snapshot.position;
  final peerPosition = peer.target.snapshot.position;
  await _until(
    tester,
    () =>
        host.target.snapshot.playing &&
        peer.target.snapshot.playing &&
        host.target.snapshot.position - hostPosition >=
            const Duration(milliseconds: 350) &&
        peer.target.snapshot.position - peerPosition >=
            const Duration(milliseconds: 350),
    'observed further progress from both native decoders',
    host,
    peer: peer,
  );
  expect(
    peer.errors,
    isEmpty,
    reason: 'The real peer bridge must remain healthy.',
  );
}

Future<void> _pauseTogether(WidgetTester tester, _Host host, _Peer peer) async {
  if (host.target.snapshot.playing) await host.app.togglePlay();
  await _until(
    tester,
    () => !host.target.snapshot.playing && !peer.target.snapshot.playing,
    'both native decoders paused',
    host,
    peer: peer,
  );
}

/// Isolate Android audio-focus behavior from Syncplay, quota and SDK purchases.
/// Both targets are real native decoders; neither is attached to a bridge.
Future<void> _verifyDecoderCoexistence(
  WidgetTester tester,
  Map<String, Object?> evidence,
) async {
  final first = LocalMobileTarget(mixWithOthers: true);
  final second = LocalMobileTarget(mixWithOthers: true);
  final elapsed = Stopwatch()..start();
  final transitions = <Map<String, Object?>>[];
  evidence['transitions'] = transitions;
  final previous = <String, String>{};
  void record(String name, PlaybackSnapshot state, {String? command}) {
    final signature = '${state.playing}/${state.buffering}/${state.connection}';
    if (command == null && previous[name] == signature) return;
    previous[name] = signature;
    final event = <String, Object?>{
      'elapsedMs': elapsed.elapsedMilliseconds,
      'target': name,
      'command': ?command,
      'playing': state.playing,
      'buffering': state.buffering,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'connection': state.connection.name,
      'error': state.error,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    };
    if (transitions.length == 80) transitions.removeAt(0);
    transitions.add(event);
    debugPrint('HOSTING_DECODER ${jsonEncode(event)}');
  }

  final firstEvents = first.states.listen((state) => record('first', state));
  final secondEvents = second.states.listen((state) => record('second', state));
  Future<void> advance(
    bool Function() ready,
    String stage, {
    bool bothPlaying = false,
  }) async {
    final timer = Stopwatch()..start();
    final pausedSince = <String, Duration>{};
    while (!ready()) {
      if (bothPlaying) {
        for (final entry in {'first': first, 'second': second}.entries) {
          final state = entry.value.snapshot;
          if (state.playing || state.buffering) {
            pausedSince.remove(entry.key);
          } else {
            // Native events can briefly trail play(). Explicit buffering is
            // distinct from pause; an unbuffered pause must converge promptly.
            final since = pausedSince.putIfAbsent(
              entry.key,
              () => timer.elapsed,
            );
            expect(
              timer.elapsed - since,
              lessThan(const Duration(seconds: 2)),
              reason:
                  '$stage: ${entry.key} stayed paused without buffering; '
                  '${jsonEncode(transitions)}',
            );
          }
        }
      }
      if (timer.elapsed > const Duration(seconds: 35)) {
        throw TestFailure(
          '$stage timed out: first=${first.snapshot.position} '
          'playing=${first.snapshot.playing}, second=${second.snapshot.position} '
          'playing=${second.snapshot.playing}',
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  try {
    final media = MediaItem.fromUrl(_video);
    await first.load(media);
    await second.load(media);
    _expectMedia(first);
    _expectMedia(second);
    // Consume both native textures just as the main runtime view does.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final target in [first, second])
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: target.controller!.value.aspectRatio,
                      child: VideoPlayer(target.controller!),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    record('first', first.snapshot, command: 'play');
    await first.play();
    await advance(
      () => first.snapshot.position >= const Duration(milliseconds: 800),
      'first decoder starts alone',
    );
    final firstStart = first.snapshot.position;
    final secondStart = second.snapshot.position;
    record('second', second.snapshot, command: 'play');
    await second.play();
    await advance(
      () =>
          first.snapshot.playing &&
          second.snapshot.playing &&
          first.snapshot.position - firstStart >=
              const Duration(milliseconds: 1500) &&
          second.snapshot.position - secondStart >=
              const Duration(milliseconds: 1500),
      'two native decoders retain playback after second start',
      bothPlaying: true,
    );
    expect(first.snapshot.playing, isTrue);
    expect(second.snapshot.playing, isTrue);
    evidence['firstAdvanceMs'] =
        (first.snapshot.position - firstStart).inMilliseconds;
    evidence['secondAdvanceMs'] =
        (second.snapshot.position - secondStart).inMilliseconds;
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await firstEvents.cancel();
      await secondEvents.cancel();
      try {
        await second.close();
      } finally {
        await first.close();
      }
    }
  }
}

Future<BillingResult> _purchase(
  WidgetTester tester,
  _Host host,
  _Peer? peer,
  String outcome,
) async {
  await tester.pumpWidget(
    _RuntimeView(host: host, peer: peer, stage: 'Native Test Store: $outcome'),
  );
  await tester.pump();
  debugPrint('RC_SMOKE_STAGE $outcome');
  return host.billing
      .purchase(host.monthly)
      .timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TestFailure(
          'Native Test Store $outcome was not selected within 90s.',
        ),
      );
}

class _Host {
  _Host(
    this.app,
    this.billing,
    this.quota,
    this.target,
    this.quotaFile,
    this.clients,
  );
  final AppController app;
  final RevenueCatBillingService billing;
  final LocalHostingAccessPolicy quota;
  final LocalMobileTarget target;
  final File quotaFile;
  final List<SyncplayClient> clients;
  Package get monthly =>
      billing.packages.singleWhere((item) => item.identifier == r'$rc_monthly');

  static Future<_Host> open(Directory root) async {
    final repository = AppRepository(File('${root.path}/history.json'));
    await repository.read();
    final billing = RevenueCatBillingService(apiKey: _apiKey);
    final target = LocalMobileTarget(mixWithOthers: true);
    final file = File('${root.path}/quota.json');
    final quota = LocalHostingAccessPolicy(
      store: FileHostingQuotaStore(file),
      isPlus: () => billing.isPlus,
    );
    final clients = <SyncplayClient>[];
    final app = AppController(
      repository: repository,
      billing: billing,
      hosting: quota,
      phone: target,
      createSyncClient: () {
        final client = SyncplayClient();
        clients.add(client);
        return client;
      },
    );
    try {
      _expectSuccess(
        await billing.configure().timeout(const Duration(seconds: 60)),
        'configure',
      );
      await Purchases.invalidateCustomerInfoCache();
      _expectSuccess(
        await billing.refresh().timeout(const Duration(seconds: 60)),
        'fresh customer',
      );
      return _Host(app, billing, quota, target, file, clients);
    } catch (_) {
      await app.close();
      rethrow;
    }
  }
}

class _Peer {
  _Peer(this.sync, this.target, this.bridge, this.errors);
  final SyncplayClient sync;
  final LocalMobileTarget target;
  final PlaybackSyncBridge bridge;
  final List<String> errors;
  bool _closed = false;

  static Future<_Peer> open(RoomConfig config, MediaItem media) async {
    final sync = SyncplayClient();
    final target = LocalMobileTarget(mixWithOthers: true);
    final errors = <String>[];
    final bridge = PlaybackSyncBridge(
      target: target,
      sync: sync,
      // This client is a guest; hosts alone pass the billing/quota boundary.
      authorizePlayback: () async => true,
      onError: (error) => errors.add(error.toString()),
    );
    final peer = _Peer(sync, target, bridge, errors);
    try {
      final error = await sync.connectUntilJoin(
        server: config.server,
        port: config.port,
        room: config.room,
        username: 'HostingPeer',
      );
      expect(error, isNull, reason: 'Real guest STARTTLS join failed.');
      expect(sync.hasCompletedHello, isTrue);
      bridge.start();
      await bridge.load(media);
      _expectMedia(target);
      return peer;
    } catch (_) {
      await peer.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await bridge.dispose();
    } finally {
      try {
        await sync.dispose();
      } finally {
        await target.close();
      }
    }
  }
}

/// Explicit runtime harness, not the production paywall or a two-device demo.
class _RuntimeView extends StatelessWidget {
  const _RuntimeView({
    required this.host,
    required this.peer,
    required this.stage,
  });
  final _Host host;
  final _Peer? peer;
  final String stage;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('Hosting + Test Store verification')),
      body: AnimatedBuilder(
        animation: host.app,
        builder: (_, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(stage),
            Text(
              'Real TLS peers: ${host.app.peers.length} · Plus: ${host.billing.isPlus} · Upgrade needed: ${host.app.needsPlus}',
            ),
            const Text('Host — actual Android decoder'),
            if (host.target.controller case final controller?)
              AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            const SizedBox(height: 12),
            if (peer?.target.controller case final controller?) ...[
              const Text('Guest — second decoder, same Android process'),
              AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
