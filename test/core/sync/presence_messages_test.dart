import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/presence_messages.dart';

void main() {
  group('peerDepartureMessage', () {
    test('clean leave', () {
      expect(
        peerDepartureMessage(username: 'Alice', clean: true),
        'Alice left the room.',
      );
    });

    test('lost connection', () {
      expect(
        peerDepartureMessage(username: 'Bob', clean: false),
        'Bob lost connection.',
      );
    });
  });

  group('peerJoinMessage', () {
    test('first join', () {
      expect(
        peerJoinMessage(username: 'Alice', reconnected: false),
        'Alice joined the room.',
      );
    });

    test('reconnect', () {
      expect(
        peerJoinMessage(username: 'Bob', reconnected: true),
        'Bob reconnected.',
      );
    });
  });

  group('isConnectionDrop', () {
    test('connected → reconnecting is a drop', () {
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.reconnecting,
        ),
        isTrue,
      );
    });

    test('repeated backoff (handshaking → reconnecting) is not a drop', () {
      // Avoids re-announcing "connection lost" on every retry attempt.
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.handshaking,
          next: SyncConnectionStatus.reconnecting,
        ),
        isFalse,
      );
    });

    test('connected → connected is not a drop', () {
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.connected,
        ),
        isFalse,
      );
    });
  });

  group('isReconnectSuccess', () {
    test('latched + arriving at connected is a success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: true,
          next: SyncConnectionStatus.connected,
        ),
        isTrue,
      );
    });

    test('fires across the intermediate handshaking state', () {
      // The reconnect path is connected → reconnecting → handshaking →
      // connected. The latch (set on the drop) must survive handshaking so the
      // success still fires when connected finally arrives.
      var wasReconnecting = false;
      // Drop:
      if (isConnectionDrop(
        prev: SyncConnectionStatus.connected,
        next: SyncConnectionStatus.reconnecting,
      )) {
        wasReconnecting = true;
      }
      // Intermediate handshaking — not connected, no success yet:
      expect(
        isReconnectSuccess(
          wasReconnecting: wasReconnecting,
          next: SyncConnectionStatus.handshaking,
        ),
        isFalse,
      );
      // Connected — success now fires:
      expect(
        isReconnectSuccess(
          wasReconnecting: wasReconnecting,
          next: SyncConnectionStatus.connected,
        ),
        isTrue,
      );
    });

    test('first connect (no latch) is not a reconnect success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: false,
          next: SyncConnectionStatus.connected,
        ),
        isFalse,
      );
    });

    test('latched but not yet connected is not a success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: true,
          next: SyncConnectionStatus.reconnecting,
        ),
        isFalse,
      );
    });
  });

  group('ownGhostNameOnReconnect', () {
    test('reconnect: prior name not handed back → it is our ghost', () {
      // We held "meowPEOW" before the drop; this reconnect handed back
      // "meowPEOW_" because our own dropped session still occupies "meowPEOW".
      // That lingering ghost is about to be reaped — its departure must not read
      // as a peer drop.
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: 'meowPEOW',
          assignedName: 'meowPEOW_',
        ),
        'meowPEOW',
      );
    });

    test('reconnect: prior name handed back (was free) → no ghost', () {
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: 'meowPEOW',
          assignedName: 'meowPEOW',
        ),
        isNull,
      );
    });

    test('reconnect with no assigned name → no ghost', () {
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: 'meowPEOW',
          assignedName: null,
        ),
        isNull,
      );
    });

    test('first connect (no prior name) → no ghost', () {
      // A first connect has no prior session of ours, so a suffix means a
      // genuinely different user already holds the name. Forwarding their
      // departure is correct (#93) — never suppress it.
      expect(
        ownGhostNameOnReconnect(
          reconnected: false,
          previousAssignedName: null,
          assignedName: 'meowPEOW_',
        ),
        isNull,
      );
    });

    test('reconnect: real namesake hands back our same suffixed name → no '
        'ghost', () {
      // A real peer owns "meow", so the server suffixed us to "meow_" on the
      // first connect and hands "meow_" back on reconnect too. Keying on the
      // prior assigned name means we never name "meow" (the peer) — suppressing
      // its departure would hide a real friend leaving (Codex P2, the #93
      // reconnect-window ambiguity).
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: 'meow_',
          assignedName: 'meow_',
        ),
        isNull,
      );
    });

    test('reconnect: compounding suffix orphans the prior suffixed name', () {
      // We were "meowPEOW_"; the original "meowPEOW" ghost got reaped, so this
      // reconnect reclaims the clean "meowPEOW" while our just-dropped
      // "meowPEOW_" session lingers. The ghost is that prior suffixed name.
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: 'meowPEOW_',
          assignedName: 'meowPEOW',
        ),
        'meowPEOW_',
      );
    });
  });

  group('isPeerReconnect', () {
    final now = DateTime(2026, 6, 7, 12, 0, 0);

    test('null departedAt → false', () {
      expect(isPeerReconnect(departedAt: null, now: now), isFalse);
    });

    test('departed just now → true', () {
      final recent = now.subtract(const Duration(seconds: 10));
      expect(isPeerReconnect(departedAt: recent, now: now), isTrue);
    });

    test('departed exactly at window boundary → true', () {
      final atBoundary = now.subtract(const Duration(seconds: 60));
      expect(isPeerReconnect(departedAt: atBoundary, now: now), isTrue);
    });

    test('departed just past window → false', () {
      final tooOld = now.subtract(const Duration(seconds: 61));
      expect(isPeerReconnect(departedAt: tooOld, now: now), isFalse);
    });

    test('custom window respected', () {
      final recent = now.subtract(const Duration(seconds: 30));
      expect(
        isPeerReconnect(
          departedAt: recent,
          now: now,
          window: const Duration(seconds: 20),
        ),
        isFalse,
      );
      expect(
        isPeerReconnect(
          departedAt: recent,
          now: now,
          window: const Duration(seconds: 45),
        ),
        isTrue,
      );
    });
  });

  group('isFailedInitialJoin', () {
    test('error before a completed login is a failed join', () {
      expect(
        isFailedInitialJoin(
          status: SyncConnectionStatus.error,
          everConnected: false,
        ),
        isTrue,
      );
    });

    test('error after a completed login stays in the session', () {
      expect(
        isFailedInitialJoin(
          status: SyncConnectionStatus.error,
          everConnected: true,
        ),
        isFalse,
      );
    });

    test('a dead candidate during a public walk is not a failed join', () {
      expect(
        isFailedInitialJoin(
          status: SyncConnectionStatus.error,
          everConnected: false,
          lookingForServer: true,
        ),
        isFalse,
      );
    });

    test('connecting and handshaking are not a failed join', () {
      expect(
        isFailedInitialJoin(
          status: SyncConnectionStatus.connecting,
          everConnected: false,
        ),
        isFalse,
      );
      expect(
        isFailedInitialJoin(
          status: SyncConnectionStatus.handshaking,
          everConnected: false,
        ),
        isFalse,
      );
    });
  });
}
