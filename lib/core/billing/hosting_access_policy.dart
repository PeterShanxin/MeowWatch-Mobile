import 'dart:async';
import 'dart:convert';

/// Writes must replace the entire value or throw. Use one policy per store.
abstract interface class HostingQuotaStore {
  Future<String?> read();
  Future<void> write(String value);
}

enum SessionStartResult {
  guest,
  notStarted,
  alreadyStarted,
  freeStarted,
  plusStarted,
  quotaExceeded;

  bool get allowed => this != quotaExceeded;
}

abstract interface class HostingAccessPolicy {
  Future<bool> canHostNow({String? sessionId});
  Future<int> remainingFreeHostsToday();
  Future<SessionStartResult> recordSessionStarted({
    required String sessionId,
    required bool isCreator,
    required int peerCount,
    required bool synchronizedPlaybackActive,
    bool explicitStart = false,
  });
}

/// Local, device-clock-based accounting. This is not fraud prevention.
/// A persistent session ID belongs to a room lifecycle, not a connection or
/// playback target. The caller persists that ID before creating the room.
class LocalHostingAccessPolicy implements HostingAccessPolicy {
  LocalHostingAccessPolicy({
    required HostingQuotaStore store,
    required bool Function() isPlus,
    DateTime Function() clock = DateTime.now,
    // Public named parameters initialize private implementation fields.
    // ignore: prefer_initializing_formals
  }) : _store = store,
       // ignore: prefer_initializing_formals
       _isPlus = isPlus,
       // ignore: prefer_initializing_formals
       _clock = clock;

  final HostingQuotaStore _store;
  final bool Function() _isPlus;
  final DateTime Function() _clock;
  Future<void> _pending = Future<void>.value();

  // Reads join the same queue so a caller never sees an allowance before a
  // previously requested consumption is committed. A failed write cannot
  // poison the queue or mutate an in-memory allowance.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String _today() {
    final now = _clock().toLocal();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<_Ledger> _read() async {
    final stored = await _store.read();
    return stored == null ? _Ledger({}) : _Ledger.decode(stored);
  }

  @override
  Future<bool> canHostNow({String? sessionId}) => _serial(() async {
    if (_isPlus()) return true;
    final ledger = await _read();
    return (sessionId != null && ledger.sessions.containsKey(sessionId)) ||
        !ledger.freeUsedOn(_today());
  });

  @override
  Future<int> remainingFreeHostsToday() => _serial(() async {
    final ledger = await _read();
    return ledger.freeUsedOn(_today()) ? 0 : 1;
  });

  @override
  Future<SessionStartResult> recordSessionStarted({
    required String sessionId,
    required bool isCreator,
    required int peerCount,
    required bool synchronizedPlaybackActive,
    bool explicitStart = false,
  }) => _serial(() async {
    if (!isCreator) return SessionStartResult.guest;
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Must be persistent');
    }
    if (peerCount < 1 || (!synchronizedPlaybackActive && !explicitStart)) {
      return SessionStartResult.notStarted;
    }
    final ledger = await _read();
    if (ledger.sessions.containsKey(sessionId)) {
      return SessionStartResult.alreadyStarted;
    }
    final today = _today();
    final plus = _isPlus();
    if (!plus && ledger.freeUsedOn(today)) {
      return SessionStartResult.quotaExceeded;
    }
    ledger.sessions[sessionId] = _StartedSession(today, !plus);
    // Grant only after durable commit. A restart sees either the prior ledger
    // or this whole session, never a consumed date without its resumable ID.
    await _store.write(ledger.encode());
    return plus
        ? SessionStartResult.plusStarted
        : SessionStartResult.freeStarted;
  });
}

class _StartedSession {
  _StartedSession(this.date, this.usedFreeHost);
  final String date;
  final bool usedFreeHost;
}

class _Ledger {
  _Ledger(this.sessions);
  final Map<String, _StartedSession> sessions;

  bool freeUsedOn(String date) => sessions.values.any(
    (session) => session.date == date && session.usedFreeHost,
  );

  String encode() => jsonEncode({
    'version': 1,
    'sessions': sessions.map(
      (id, session) => MapEntry(id, {
        'date': session.date,
        'usedFreeHost': session.usedFreeHost,
      }),
    ),
  });

  static _Ledger decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['sessions'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid hosting allowance data');
    }
    final sessions = <String, _StartedSession>{};
    for (final entry in (value['sessions'] as Map<String, dynamic>).entries) {
      final item = entry.value;
      if (entry.key.trim().isEmpty ||
          item is! Map<String, dynamic> ||
          item['date'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(item['date'] as String) ||
          item['usedFreeHost'] is! bool) {
        throw const FormatException('Invalid hosted session data');
      }
      sessions[entry.key] = _StartedSession(
        item['date'] as String,
        item['usedFreeHost'] as bool,
      );
    }
    return _Ledger(sessions);
  }
}
