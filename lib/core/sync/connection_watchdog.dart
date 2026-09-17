import 'dart:async';

/// Detects a *silently* dead connection. The Syncplay server sends a State
/// heartbeat roughly once a second; if those stop arriving without the socket
/// cleanly closing (a half-open TCP — server vanished, NAT idle-eviction, wifi
/// blip — where onDone/onError never fire), the client would otherwise sit on
/// "connected" forever, writing into a black hole.
///
/// The watchdog watches the gap between *incoming* bytes: [bump] is called on
/// every chunk received, resetting the countdown. If nothing arrives within
/// [timeout], [onTimeout] fires once so the client can tear the link down and
/// reconnect.
class ConnectionWatchdog {
  ConnectionWatchdog({required this.timeout, required this.onTimeout});

  /// How long a silence is tolerated before the link is presumed dead. Must be
  /// comfortably larger than the server's heartbeat interval (~1s) so a slow
  /// round-trip never trips it.
  final Duration timeout;

  /// Called once when [timeout] elapses with no intervening [bump].
  final void Function() onTimeout;

  Timer? _timer;

  /// Reset the countdown. Call on every byte received from the server.
  void bump() {
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  /// Stop watching — manual disconnect or dispose. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isRunning => _timer?.isActive ?? false;
}

/// Capped exponential backoff for reconnect attempts: attempt 0 → [base], then
/// doubling each attempt up to [max]. Keeps a flaky network (or a downed
/// server) from being hammered with reconnects.
Duration reconnectBackoff({
  required int attempt,
  Duration base = const Duration(seconds: 1),
  Duration max = const Duration(seconds: 30),
}) {
  final n = attempt < 0 ? 0 : (attempt > 20 ? 20 : attempt);
  final ms = base.inMilliseconds * (1 << n);
  return Duration(
    milliseconds: ms > max.inMilliseconds ? max.inMilliseconds : ms,
  );
}
