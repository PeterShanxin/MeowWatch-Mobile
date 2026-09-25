import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';

import '../../integration_test/support/local_day_quota.dart';

void main() {
  test('midnight refreshes allowance without another session charge', () async {
    var now = DateTime(2026, 9, 24, 23, 59, 59);
    final store = _Store();
    final policy = LocalHostingAccessPolicy(
      store: store,
      isPlus: () => false,
      clock: () => now,
    );
    expect(
      await policy.recordSessionStarted(
        sessionId: 'original-room',
        isCreator: true,
        peerCount: 1,
        synchronizedPlaybackActive: true,
      ),
      SessionStartResult.freeStarted,
    );
    final originalLedger = store.value;
    final sameDay = await verifyFreeAllowanceToday(
      policy,
      chargedLocalDate: '2026-09-24',
      clock: () => now,
    );
    expect((sameDay['remaining'] as Map)['actual'], 0);
    now = DateTime(2026, 9, 25, 0, 0, 1);
    final nextDay = await verifyFreeAllowanceToday(
      policy,
      chargedLocalDate: '2026-09-24',
      clock: () => now,
    );
    expect((nextDay['remaining'] as Map)['actual'], 1);
    expect((nextDay['canHostNewRoom'] as Map)['actual'], true);
    expect(store.value, originalLedger);
  });

  test('a policy read itself can cross midnight', () async {
    var now = DateTime(2026, 9, 24, 23, 59, 59);
    final store = _Store();
    final policy = LocalHostingAccessPolicy(
      store: store,
      isPlus: () => false,
      clock: () => now,
    );
    await policy.recordSessionStarted(
      sessionId: 'original-room',
      isCreator: true,
      peerCount: 1,
      synchronizedPlaybackActive: true,
    );
    store.onRead = () {
      now = DateTime(2026, 9, 25);
    };
    final receipt = await verifyFreeAllowanceToday(
      policy,
      chargedLocalDate: '2026-09-24',
      clock: () => now,
    );
    expect((receipt['remaining'] as Map)['crossedMidnight'], true);
    expect((receipt['remaining'] as Map)['actual'], 1);
  });

  test('uncharged guest keeps its allowance across days', () async {
    final now = DateTime(2026, 9, 25);
    final policy = LocalHostingAccessPolicy(
      store: _Store(),
      isPlus: () => false,
      clock: () => now,
    );
    final receipt = await verifyFreeAllowanceToday(
      policy,
      chargedLocalDate: null,
      clock: () => now,
    );
    expect((receipt['remaining'] as Map)['actual'], 1);
  });

  test('calendar handling cannot forgive an unrecorded charge', () async {
    final now = DateTime(2026, 9, 24, 23, 59);
    final policy = LocalHostingAccessPolicy(
      store: _Store(),
      isPlus: () => false,
      clock: () => now,
    );
    await expectLater(
      verifyFreeAllowanceToday(
        policy,
        chargedLocalDate: '2026-09-24',
        clock: () => now,
      ),
      throwsStateError,
    );
  });
}

class _Store implements HostingQuotaStore {
  String? value;
  void Function()? onRead;
  @override
  Future<String?> read() async {
    onRead?.call();
    return value;
  }

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
