import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_core.dart';

class FakeSyncCore extends SyncCore {
  bool connected = false;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    connected = true;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connected),
    );
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  void pushPeer(PeerPlayState s) => emitPeerState(s);

  void pushActivity(SyncActivity a) => emitActivity(a);
}

void main() {
  late FakeSyncCore core;

  setUp(() => core = FakeSyncCore());
  tearDown(() async => core.dispose());

  test('connect emits connected state', () async {
    final states = <SyncConnectionState>[];
    final sub = core.connectionState.listen(states.add);
    await core.connect(server: 's', port: 1, username: 'u', room: 'r');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(states.last.status, SyncConnectionStatus.connected);
    expect(core.lastConnectionState?.status, SyncConnectionStatus.connected);
  });

  test('peer state stream emits pushed states', () async {
    final peers = <PeerPlayState>[];
    final sub = core.peerState.listen(peers.add);
    core.pushPeer(
      const PeerPlayState(position: Duration(seconds: 3), paused: false),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(peers.single.position, const Duration(seconds: 3));
  });

  test('activity stream emits pushed activities', () async {
    final events = <SyncActivity>[];
    final sub = core.activity.listen(events.add);
    core.pushActivity(
      const SyncActivity(
        kind: SyncActivityKind.paused,
        username: 'lin',
        position: Duration(seconds: 42),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.single.kind, SyncActivityKind.paused);
    expect(events.single.username, 'lin');
  });
}
