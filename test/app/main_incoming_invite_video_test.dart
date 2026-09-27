import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/app/incoming_links.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/session/room_invite.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/main.dart';

import '../support/sync_playback_fakes.dart';
import '../ui/home/ui_test_support.dart';

/// Joins instantly without touching a socket, mirroring `ControlledClient` in
/// app_controller_test.dart.
class _JoinableClient extends SyncplayClient {
  @override
  Future<String?> connectUntilJoin({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
    Future<void> Function()? onHandoff,
  }) async {
    emitConnectionState(
      SyncConnectionState(
        status: SyncConnectionStatus.connected,
        username: username,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return null;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {}
  @override
  void updateLocalState({required Duration position, required bool paused}) {}
  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}
  @override
  Future<void> disposeBackend() async {}
}

/// Refuses the join immediately without touching a socket.
class _FailingClient extends SyncplayClient {
  @override
  Future<String?> connectUntilJoin({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
    Future<void> Function()? onHandoff,
  }) async => 'Could not reach that server.';

  @override
  void notifyLocalChange({required bool doSeek}) {}
  @override
  void updateLocalState({required Duration position, required bool paused}) {}
  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}
  @override
  Future<void> disposeBackend() async {}
}

final class _FakeIncomingLinkSource implements IncomingLinkSource {
  _FakeIncomingLinkSource(Uri initial) : _initial = Future.value(initial);

  final Future<Uri?> _initial;
  final StreamController<Uri> _changes = StreamController<Uri>();

  @override
  Future<Uri?> getInitialLink() => _initial;

  @override
  Stream<Uri> get uriLinkStream => _changes.stream;

  Future<void> close() => _changes.close();
}

Future<void> _pumpRoute(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('confirming a video invite joins the room and opens the video', (
    tester,
  ) async {
    final repository = UiTestRepository();
    final app = AppController(
      repository: repository,
      billing: UiTestBilling(),
      hosting: UiTestHosting(),
      phone: SyncTestTarget(),
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () => _JoinableClient(),
    );
    await app.setName('Milo');

    final invite = encodeRoomInvite(
      const RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'quiet-otter',
        username: 'Host',
      ),
      media: MediaItem.fromUrl('https://video.example/movie.mp4'),
    );
    final linkSource = _FakeIncomingLinkSource(invite);

    await tester.pumpWidget(
      MainApp(controller: app, incomingLinkSource: linkSource),
    );
    await _pumpRoute(tester);

    expect(find.text('Room invitation received'), findsOneWidget);
    expect(find.text('Room: quiet-otter'), findsOneWidget);
    expect(find.text('Video: video.example/movie.mp4'), findsOneWidget);
    expect(app.room, isNull);
    expect(app.target.snapshot.media, isNull);

    await tester.tap(find.byKey(const Key('join-submit-button')));
    await _pumpRoute(tester);

    expect(app.room?.config.room, 'quiet-otter');
    expect(
      app.target.snapshot.media?.uri,
      Uri.parse('https://video.example/movie.mp4'),
    );
    expect(app.inPlayer, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await app.close();
      await linkSource.close();
    });
  });

  test('a failed join leaves the room and player untouched', () async {
    final app = AppController(
      repository: UiTestRepository(),
      billing: UiTestBilling(),
      hosting: UiTestHosting(),
      phone: SyncTestTarget(),
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () => _FailingClient(),
    );
    final invite = encodeRoomInvite(
      const RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'quiet-otter',
        username: 'Host',
      ),
      media: MediaItem.fromUrl('https://video.example/movie.mp4'),
    );

    // Mirrors main.dart's `_joinRoomWithVideo`: a failed join must short
    // circuit before any video load is attempted.
    final joined = await app.joinRoom(invite.toString());

    expect(joined, isFalse);
    expect(app.room, isNull);
    expect(app.target.snapshot.media, isNull);
    await app.close();
  });
}
