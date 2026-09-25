import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';

String localCalendarDate(DateTime instant) =>
    instant.toLocal().toIso8601String().substring(0, 10);

/// Check each real policy read against the calendar days during that read.
/// A long native journey can cross midnight without consuming a new session.
Future<Map<String, Object?>> verifyFreeAllowanceToday(
  HostingAccessPolicy hosting, {
  required String? chargedLocalDate,
  DateTime Function() clock = DateTime.now,
}) async {
  Future<Map<String, Object?>> check<T>(
    Future<T> Function() read,
    T Function(bool usedToday) expected,
  ) async {
    final before = clock().toLocal();
    final actual = await read();
    final after = clock().toLocal();
    if (after.isBefore(before) || after.difference(before).inDays > 0) {
      throw StateError('Quota observation crossed an invalid clock interval.');
    }
    final dates = {localCalendarDate(before), localCalendarDate(after)};
    final allowed = dates.map((date) => expected(date == chargedLocalDate));
    if (!allowed.contains(actual)) {
      throw StateError('Free allowance does not match the observed local day.');
    }
    return {
      'beforeLocal': before.toIso8601String(),
      'afterLocal': after.toIso8601String(),
      'observedLocalDates': dates.toList(),
      'crossedMidnight': dates.length > 1,
      'actual': actual,
    };
  }

  return {
    'chargedLocalDate': chargedLocalDate,
    'remaining': await check(
      hosting.remainingFreeHostsToday,
      (used) => used ? 0 : 1,
    ),
    'canHostNewRoom': await check(hosting.canHostNow, (used) => !used),
  };
}
