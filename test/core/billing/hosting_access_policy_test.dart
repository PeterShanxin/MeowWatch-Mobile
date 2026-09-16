import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';

class MemoryStore implements HostingQuotaStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrites) throw const FileSystemException('Storage unavailable');
    this.value = value;
  }
}

void main() {
  late MemoryStore store;
  late LocalHostingAccessPolicy policy;
  late DateTime now;
  late bool plus;

  LocalHostingAccessPolicy createPolicy() => LocalHostingAccessPolicy(
    store: store,
    isPlus: () => plus,
    clock: () => now,
  );

  Future<SessionStartResult> start(
    String id, {
    bool creator = true,
    int peers = 1,
    bool playing = true,
    bool explicit = false,
  }) => policy.recordSessionStarted(
    sessionId: id,
    isCreator: creator,
    peerCount: peers,
    synchronizedPlaybackActive: playing,
    explicitStart: explicit,
  );

  setUp(() {
    now = DateTime(2026, 9, 16, 23, 59);
    plus = false;
    store = MemoryStore();
    policy = createPolicy();
  });

  test(
    'creating alone or waiting for playback never consumes allowance',
    () async {
      expect(await policy.canHostNow(), isTrue);
      expect(await start('room', peers: 0), SessionStartResult.notStarted);
      expect(
        await start('room', playing: false),
        SessionStartResult.notStarted,
      );
      expect(await policy.remainingFreeHostsToday(), 1);
      expect(store.value, isNull);
      expect(await start('room'), SessionStartResult.freeStarted);
      expect(await policy.remainingFreeHostsToday(), 0);
      expect(await policy.canHostNow(), isFalse);
      expect(await start('second'), SessionStartResult.quotaExceeded);
    },
  );

  test(
    'guest never reads or writes quota even when allowance is exhausted',
    () async {
      await start('host');
      final before = store.value;
      expect(await start('guest', creator: false), SessionStartResult.guest);
      expect(store.value, before);
      store.value = 'corrupt';
      expect(await start('guest', creator: false), SessionStartResult.guest);
    },
  );

  test('explicit start still requires a real peer', () async {
    expect(
      await start('room', peers: 0, playing: false, explicit: true),
      SessionStartResult.notStarted,
    );
    expect(
      await start('room', playing: false, explicit: true),
      SessionStartResult.freeStarted,
    );
  });

  test(
    'replay, reconnect, restart and target change reuse persistent ID',
    () async {
      await start('persistent-session');
      final before = store.value;
      policy = createPolicy();
      expect(await policy.canHostNow(sessionId: 'persistent-session'), isTrue);
      expect(
        await start('persistent-session'),
        SessionStartResult.alreadyStarted,
      );
      expect(store.value, before);
      expect(await policy.remainingFreeHostsToday(), 0);
    },
  );

  test(
    'midnight resets allowance but old-session replay does not use it',
    () async {
      await start('yesterday');
      now = DateTime(2026, 9, 17);
      policy = createPolicy();
      expect(await policy.remainingFreeHostsToday(), 1);
      expect(await start('yesterday'), SessionStartResult.alreadyStarted);
      expect(await policy.remainingFreeHostsToday(), 1);
      expect(await start('today'), SessionStartResult.freeStarted);
      expect(await policy.canHostNow(sessionId: 'yesterday'), isTrue);
      expect(await policy.canHostNow(), isFalse);
    },
  );

  test(
    'returning to a previously consumed date does not reset its quota',
    () async {
      await start('day-one');
      now = DateTime(2026, 9, 17);
      await start('day-two');
      now = DateTime(2026, 9, 16);
      expect(await policy.remainingFreeHostsToday(), 0);
    },
  );

  test(
    'Plus uses entitlement callback and sessions survive entitlement expiry',
    () async {
      await start('free');
      plus = true;
      expect(await policy.canHostNow(), isTrue);
      expect(await start('plus-one'), SessionStartResult.plusStarted);
      expect(await start('plus-two'), SessionStartResult.plusStarted);
      plus = false;
      expect(await policy.canHostNow(), isFalse);
      expect(await start('plus-one'), SessionStartResult.alreadyStarted);
      expect(await start('third'), SessionStartResult.quotaExceeded);
    },
  );

  test('concurrent starts commit exactly one free session', () async {
    final results = await Future.wait([start('one'), start('two')]);
    expect(results, [
      SessionStartResult.freeStarted,
      SessionStartResult.quotaExceeded,
    ]);
  });

  test('concurrent replay is idempotent', () async {
    expect(await Future.wait([start('one'), start('one')]), [
      SessionStartResult.freeStarted,
      SessionStartResult.alreadyStarted,
    ]);
  });

  test(
    'failed persistence grants nothing and subsequent retry can recover',
    () async {
      store.failWrites = true;
      await expectLater(start('one'), throwsA(isA<FileSystemException>()));
      expect(await policy.remainingFreeHostsToday(), 1);
      expect(store.value, isNull);
      store.failWrites = false;
      expect(await start('one'), SessionStartResult.freeStarted);
      expect(await policy.remainingFreeHostsToday(), 0);
    },
  );

  test(
    'malformed stored data fails closed instead of resetting quota',
    () async {
      store.value = '{"version": 1, "sessions": {"a": {"date": false}}}';
      await expectLater(policy.canHostNow(), throwsFormatException);
      await expectLater(start('one'), throwsFormatException);
      expect(store.value, contains('false'));
    },
  );

  test(
    'real file replacement survives fresh store and ignores partial temp',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'meowwatch-quota-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/quota.json');
      final disk = FileHostingQuotaStore(file);
      expect(await disk.read(), isNull);
      policy = LocalHostingAccessPolicy(
        store: disk,
        isPlus: () => false,
        clock: () => now,
      );
      await start('one');
      now = DateTime(2026, 9, 17);
      await start('two');
      await File('${file.path}.pending').writeAsString('{incomplete');
      policy = LocalHostingAccessPolicy(
        store: FileHostingQuotaStore(file),
        isPlus: () => false,
        clock: () => now,
      );
      expect(await policy.remainingFreeHostsToday(), 0);
      expect(await start('one'), SessionStartResult.alreadyStarted);
      expect(await start('two'), SessionStartResult.alreadyStarted);
      now = DateTime(2026, 9, 18);
      expect(await start('three'), SessionStartResult.freeStarted);
    },
  );
}
