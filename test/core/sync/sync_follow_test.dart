import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_follow.dart';

void main() {
  group('decideFollow', () {
    test('applies a peer pause flip', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 5),
          paused: true,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.paused, isTrue);
      expect(action.position, const Duration(seconds: 5));
    });

    test('ignores our own unpause echoed back', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 5),
          paused: false,
          setBy: 'me',
        ),
        localPaused: false, // we already unpaused locally
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('applies an explicit seek made by the peer', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 60),
          paused: false,
          doSeek: true,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.position, const Duration(seconds: 60));
    });

    test('ignores our own seek echoed back', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 60),
          paused: false,
          doSeek: true,
          setBy: 'me',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 60),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does nothing on a steady heartbeat with small drift', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 11),
          paused: false,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 10),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('rewinds when local player is far ahead of the room', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 10),
          paused: false,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 20), // 10s ahead
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.position, const Duration(seconds: 10));
    });

    test('does not rewind to a setter-less global (empty-room reset to 0)', () {
      // After both clients drop and rejoin, the server's fresh room state is
      // position 0 with no setBy. We are mid-film and "far ahead" of it, but
      // must NOT rewind to that phantom zero — only a real peer position counts.
      final action = decideFollow(
        global: const PeerPlayState(position: Duration.zero, paused: false),
        localPaused: false,
        localPosition: const Duration(seconds: 500),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does not follow a setter-less phantom pause (reconnect reset to 0)', () {
      // On a brief reconnect the room momentarily empties and the server sends
      // its default state: position 0, paused, with NO setBy. We are mid-film
      // and playing. The pause/play-flip rule would otherwise apply it — pausing
      // us and yanking position back to 0. A setter-less state is never a real
      // user action, so it must be ignored (mirrors the rewind rule's guard).
      final action = decideFollow(
        global: const PeerPlayState(position: Duration.zero, paused: true),
        localPaused: false,
        localPosition: const Duration(seconds: 2591),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does not rewind when local player is behind the room', () {
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 20),
          paused: false,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 10), // 10s behind
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does not rewind to chase a stalled (frozen) peer', () {
      // Layer 2 — the rewind amplifier. A peer that claims `playing` but whose
      // position is frozen (a stuck engine) must NOT pull us into the rewind
      // sawtooth: we run >threshold ahead, rewind to the stuck spot, replay, get
      // ahead again, rewind again — forever. When the peer is flagged stalled,
      // the drift-rewind rule stands down and we keep playing smoothly instead.
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 500),
          paused: false,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(
          seconds: 510,
        ), // 10s ahead of the stuck peer
        username: 'me',
        peerStalled: true,
      );
      expect(
        action.shouldApply,
        isFalse,
        reason: 'do not rewind to chase a frozen, non-advancing peer',
      );
    });

    test('still rewinds when far ahead of a normally-advancing peer', () {
      // The stall guard must not disable healthy drift correction: with the peer
      // advancing (peerStalled=false) we still rewind when genuinely ahead.
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration(seconds: 500),
          paused: false,
          setBy: 'lin',
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 510),
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.position, const Duration(seconds: 500));
    });
  });
}
