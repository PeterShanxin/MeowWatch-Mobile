import 'dart:async';

import 'package:nearby_bridge/nearby_bridge.dart';

import '../media/media_item.dart';
import '../playback/playback_target.dart';
import 'nearby_snapshot.dart';

class NearbyDesktopTarget extends PlaybackTarget {
  NearbyDesktopTarget({required this.client, required this.credential}) {
    _events = client.events.listen(_received);
    _connection = client.states.listen((state) {
      // Broadcast delivery may lag a new explicit connection attempt.
      if (_closed || !identical(state, client.state)) return;
      if (state.phase != NearbyClientPhase.connected) {
        if ((state.phase == NearbyClientPhase.disconnected ||
                state.phase == NearbyClientPhase.disposed) &&
            _ready?.isCompleted == false) {
          _ready!.completeError(
            NearbyException(state.errorCode ?? 'not_connected'),
          );
        }
        _publishDisconnected(state.errorCode);
      }
    });
  }

  final NearbyClient client;
  final NearbyClientCredential credential;
  late final StreamSubscription<NearbyFrame> _events;
  late final StreamSubscription<NearbyClientState> _connection;
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  final _social = StreamController<NearbyFrame>.broadcast();
  NearbySnapshot? _remote;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot(
    connection: PlaybackConnection.disconnected,
  );
  Completer<void>? _ready;
  bool _closed = false;
  Future<void>? _closing;
  int _generation = 0;

  NearbySnapshot? get remote => _remote;
  Stream<NearbyFrame> get social => _social.stream;
  bool get connected =>
      !_closed &&
      client.state.phase == NearbyClientPhase.connected &&
      _remote != null;
  @override
  String get id => 'nearby:${credential.desktopId}';
  @override
  String get label => _remote?.desktopName ?? 'Nearby desktop';
  @override
  PlaybackSnapshot get snapshot => _snapshot;
  @override
  Stream<PlaybackSnapshot> get states => _states.stream;

  Future<void> connect(LanSubnet subnet, {LanEndpoint? endpoint}) async {
    if (_closed) throw const NearbyException('not_connected');
    final generation = ++_generation;
    if (_ready?.isCompleted == false) {
      _ready!.completeError(const NearbyException('cancelled'));
    }
    _remote = null;
    final ready = _ready = Completer<void>();
    // Attach the timeout handler before connect can synchronously dispatch a
    // queued initial snapshot or error, avoiding an unobserved completer error.
    final initialState = ready.future.timeout(const Duration(seconds: 15));
    try {
      await Future.wait([
        client.connect(
          credential: credential,
          subnet: subnet,
          endpoint: endpoint,
        ),
        initialState,
      ], eagerError: true);
      if (_closed || generation != _generation) {
        throw const NearbyException('cancelled');
      }
      if (!connected) throw const NearbyException('not_connected');
    } catch (_) {
      if (!_closed && generation == _generation) client.disconnect();
      rethrow;
    } finally {
      if (identical(_ready, ready)) _ready = null;
    }
  }

  void _received(NearbyFrame frame) {
    if (_closed || client.state.phase != NearbyClientPhase.connected) return;
    if (frame.type != 'state.snapshot') {
      _social.add(frame);
      return;
    }
    try {
      final remote = NearbySnapshot.parse(
        frame.fields['state']! as Map<String, Object?>,
      );
      if (remote.desktopId != credential.desktopId ||
          remote.epoch != frame.fields['sessionEpoch']) {
        throw const NearbyException('auth_failed');
      }
      _remote = remote;
      _snapshot = remote.playback;
      _publish();
      if (_ready?.isCompleted == false) _ready!.complete();
    } catch (_) {
      if (_ready?.isCompleted == false) {
        _ready!.completeError(const NearbyException('invalid_argument'));
      }
      client.disconnect();
      _publishDisconnected('invalid_argument');
    }
  }

  void _publishDisconnected(String? code) {
    if (_closed) return;
    _snapshot = PlaybackSnapshot(
      media: _snapshot.media,
      position: _snapshot.position,
      duration: _snapshot.duration,
      connection: PlaybackConnection.disconnected,
      error: code == null ? _snapshot.error : nearbyErrorMessage(code),
    );
    _publish();
  }

  void _publish() {
    if (_closed) return;
    _states.add(_snapshot);
    notifyListeners();
  }

  @override
  Future<void> load(MediaItem media, {Duration position = Duration.zero}) =>
      Future.error(const NearbyException('desktop_media_required'));
  @override
  Future<void> play() => _command('playback.play');
  @override
  Future<void> pause() => _command('playback.pause');
  @override
  Future<void> seek(Duration position) => _command('playback.seek', {
    'positionMs': position.inMilliseconds.clamp(
      0,
      _snapshot.duration > Duration.zero
          ? _snapshot.duration.inMilliseconds
          : 7 * 24 * 60 * 60 * 1000,
    ),
  });
  Future<void> sendChat(String text) => _command('chat.send', {'text': text});
  Future<void> sendReaction(String emoji) =>
      _command('chat.reaction', {'reaction': emoji});
  Future<void> sendTyping(bool active) =>
      _command('chat.typing', {'typing': active});

  Future<void> _command(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    if (!connected) throw const NearbyException('not_connected');
    await client.command(method, args);
    // Acknowledgment does not update optimistic playback; a desktop snapshot does.
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _generation++;
    if (_ready?.isCompleted == false) {
      _ready!.completeError(const NearbyException('cancelled'));
    }
    await _events.cancel();
    await _connection.cancel();
    await client.dispose();
    await _states.close();
    await _social.close();
    super.dispose();
  }
}

String nearbyErrorMessage(String code) => switch (code) {
  'lan_unavailable' =>
    'Connect your phone and desktop to the same Wi-Fi or Ethernet network.',
  'permission_denied' =>
    'Allow local network access in your device settings, then try again.',
  'pairing_expired' || 'pairing_closed' =>
    'This pairing invitation expired. Open a fresh invitation on your desktop.',
  'pairing_denied' ||
  'approval_denied' => 'The desktop declined this pairing request.',
  'controller_busy' =>
    'Another phone is controlling this desktop. Disconnect it first.',
  'storage_unavailable' =>
    'Secure device storage is unavailable. Pairing was not saved; try again after checking your device.',
  'auth_failed' || 'certificate_mismatch' || 'device_revoked' =>
    'Could not verify this desktop. Remove the saved pairing and pair again from its screen.',
  'session_changed' || 'room_mismatch' =>
    'The desktop room changed. Check its room, then reconnect.',
  'desktop_media_required' =>
    'Choose this video on your desktop. Local phone files are not transferred.',
  'no_media' => 'Choose a video on your desktop first.',
  'command_uncertain' || 'command_timeout' =>
    'The desktop did not confirm that action. Reconnect and check playback before retrying.',
  'invalid_argument' =>
    'The desktop sent an unsupported response. Update both apps and pair again.',
  _ =>
    'Connection to the desktop was lost. Reconnect or choose Watch on this phone.',
};
