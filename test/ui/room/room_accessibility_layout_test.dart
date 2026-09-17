import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_desktop_target.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_snapshot.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'DMSans': 'assets/fonts/DMSans.ttf',
      'DMSerifDisplay': 'assets/fonts/DMSerifDisplay.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final layout in [
    (name: 'small phone', size: const Size(360, 640), textScale: 2.0),
    (name: 'landscape tablet', size: const Size(1280, 800), textScale: 1.0),
  ]) {
    testWidgets('${layout.name} reveals roster through the outer room list', (
      tester,
    ) async {
      await _setView(tester, layout.size);
      final fixture = UiTestApp.create();
      fixture.controller
        ..room = const RoomTicket(
          id: 'roster-session',
          isHost: true,
          config: RoomConfig(
            server: 'syncplay.example',
            port: 8995,
            room: 'Movie night',
            username: 'Production Host',
          ),
        )
        ..connection = const SyncConnectionState(
          status: SyncConnectionStatus.connected,
        );
      fixture.controller.peers.add('Production Guest');

      await tester.pumpWidget(
        _scaledApp(
          RoomScreen(
            app: fixture.controller,
            onLoad: () {},
            onInvite: () {},
            onDevices: () {},
            onLeave: () {},
            onStartRoom: () {},
            onTogglePlay: () {},
            onSeek: (_) {},
          ),
          textScale: layout.textScale,
        ),
      );
      await tester.pump();

      expect(fixture.controller.phone.snapshot.media, isNull);
      final roomScrollables = find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      );
      expect(roomScrollables.evaluate().length, greaterThan(1));
      final roomDetails = roomScrollables.first;
      expect(roomDetails, findsOneWidget);
      expect(
        find.ancestor(of: roomDetails, matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'Select the outer list, not the nested empty video stage.',
      );

      // Use the production driver's gutter gesture: the empty stage can
      // scroll independently at 200% text and consume a center-origin drag.
      final peerLabel = find.text('Production Guest');
      for (
        var scrolls = 0;
        peerLabel.evaluate().isEmpty && scrolls < 8;
        scrolls++
      ) {
        final bounds = tester.getRect(roomDetails);
        await tester.dragFrom(
          Offset(bounds.left + 8, bounds.center.dy),
          const Offset(0, -250),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.ensureVisible(peerLabel);
      await tester.pumpAndSettle();

      expect(peerLabel.hitTestable(), findsOneWidget);
      expect(
        tester.state<ScrollableState>(roomDetails).position.pixels,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.close);
    });
  }

  testWidgets('small phone transport controls reflow at 200% text', (
    tester,
  ) async {
    await _setView(tester, const Size(360, 640));
    final fixture = UiTestApp.create();
    final target = fixture.controller.phone as SyncTestTarget;
    target.emit(
      PlaybackSnapshot(
        media: MediaItem(
          uri: Uri.parse('https://example.test/a-very-long-film.mp4'),
          title: 'A Very Long Film',
        ),
        position: const Duration(hours: 12, minutes: 34, seconds: 56),
        duration: const Duration(hours: 99, minutes: 59, seconds: 59),
        connection: PlaybackConnection.ready,
      ),
    );
    await fixture.controller.useLocalMode();
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        captureKey: capture,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Back to home'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('12:34:56'), findsOneWidget);
    expect(find.text('99:59:59'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-small-phone-player');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('native short landscape fits loaded playback and actions', (
    tester,
  ) async {
    const title =
        'Sintel — official trailer with a long descriptive title for movie night';
    await _setView(
      tester,
      const Size(800, 360),
      padding: const FakeViewPadding(left: 42.5, top: 24, bottom: 24),
    );
    final fixture = UiTestApp.create();
    final target = fixture.controller.phone as SyncTestTarget;
    target.emit(
      PlaybackSnapshot(
        media: MediaItem(
          uri: Uri.parse('https://example.test/sync-fixture.mp4'),
          title: title,
        ),
        position: const Duration(hours: 12, minutes: 34, seconds: 56),
        duration: const Duration(hours: 99, minutes: 59, seconds: 59),
        connection: PlaybackConnection.ready,
      ),
    );
    await fixture.controller.useLocalMode();
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        captureKey: capture,
        textScale: 1,
      ),
    );
    await tester.pump();

    expect(find.text('12:34:56'), findsOneWidget);
    expect(find.text('99:59:59'), findsOneWidget);
    expect(find.text('Watch together'), findsOneWidget);
    expect(find.byTooltip('Play together'), findsOneWidget);
    expect(find.text(title), findsOneWidget);
    final titleWidget = tester.widget<Text>(find.text(title));
    expect(titleWidget.maxLines, 1);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
    expect(find.text('Local mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-landscape-player');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('short landscape controls stay usable at 200% text', (
    tester,
  ) async {
    await _setView(tester, const Size(800, 360));
    final fixture = UiTestApp.create();
    await fixture.controller.useLocalMode();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose a video'), findsOneWidget);
    expect(find.text('Your own screening'), findsOneWidget);
    expect(find.text('Local mode'), findsOneWidget);
    expect(find.text('Watch together'), findsOneWidget);
    expect(find.byTooltip('Play together'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('portrait tablet bounds the player and hides paused buffering', (
    tester,
  ) async {
    await _setView(tester, const Size(800, 1280));
    final fixture = UiTestApp.create();
    final target = fixture.controller.phone as SyncTestTarget;
    target.emit(
      PlaybackSnapshot(
        media: MediaItem(
          uri: Uri.parse('https://example.test/sync-fixture.mp4'),
          title: 'sync-fixture.mp4',
        ),
        position: const Duration(seconds: 62),
        duration: const Duration(seconds: 90),
        connection: PlaybackConnection.ready,
        buffering: true,
      ),
    );
    await fixture.controller.useLocalMode();

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        textScale: 1,
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(RoomScreen)).width, 800);
    expect(tester.getSize(find.byType(Slider)).width, lessThanOrEqualTo(680));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('sync-fixture.mp4'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('chat sheet fits a short landscape viewport above the keyboard', (
    tester,
  ) async {
    await _setView(
      tester,
      const Size(800, 360),
      viewInsets: const FakeViewPadding(bottom: 180),
    );
    final fixture = UiTestApp.create();
    fixture.controller.connection = const SyncConnectionState(
      status: SyncConnectionStatus.reconnecting,
    );
    final capture = GlobalKey();

    await tester.pumpWidget(
      _scaledApp(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showChatSheet(context, fixture.controller),
            child: const Text('Open chat'),
          ),
        ),
        captureKey: capture,
      ),
    );
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close chat'), findsOneWidget);
    expect(find.text('Chat unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, capture, 'a11y-landscape-keyboard-chat');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('connected empty chat has an accessible invitation', (
    tester,
  ) async {
    await _setView(tester, const Size(360, 640));
    final fixture = UiTestApp.create();
    fixture.controller.connection = const SyncConnectionState(
      status: SyncConnectionStatus.connected,
    );

    await tester.pumpWidget(
      _scaledApp(ChatPanel(app: fixture.controller), textScale: 1),
    );

    expect(find.text('No messages yet. Say hello.'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('nearby target directs media selection to the desktop', (
    tester,
  ) async {
    await _setView(tester, const Size(412, 892));
    final fixture = UiTestApp.create();
    final target = TestNearbyTarget();
    expect(await fixture.controller.adoptNearby(target), isTrue);

    await tester.pumpWidget(
      _scaledApp(
        RoomScreen(
          app: fixture.controller,
          onLoad: () {},
          onInvite: () {},
          onDevices: () {},
          onLeave: () {},
          onStartRoom: () {},
          onTogglePlay: () {},
          onSeek: (_) {},
        ),
        textScale: 1,
      ),
    );

    expect(find.text('Living room desktop'), findsOneWidget);
    expect(
      find.text('Choose this video’s file on your desktop'),
      findsOneWidget,
    );
    expect(find.text('Choose a video'), findsNothing);
    expect(find.text('Choose on desktop'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });
}

class TestNearbyTarget extends NearbyDesktopTarget {
  TestNearbyTarget()
    : _remote = NearbySnapshot(
        desktopId: encodeBytes(List<int>.filled(16, 1)),
        desktopName: 'Living room desktop',
        epoch: encodeBytes(List<int>.filled(16, 2)),
        username: 'Milo',
        connection: SyncConnectionStatus.connected,
        playback: const PlaybackSnapshot(),
        participants: const {},
        messages: const [],
      ),
      super(
        client: NearbyClient(store: _MemoryClientStore()),
        credential: _nearbyCredential(),
      );

  final NearbySnapshot _remote;
  @override
  NearbySnapshot get remote => _remote;
  @override
  bool get connected => true;
  @override
  String get label => _remote.desktopName;
  @override
  PlaybackSnapshot get snapshot => _remote.playback;
}

class _MemoryClientStore implements NearbyClientStore {
  @override
  Future<NearbyClientCredential?> read(String desktopId) async => null;
  @override
  Future<void> remove(String desktopId) async {}
  @override
  Future<void> write(NearbyClientCredential credential) async {}
}

NearbyClientCredential _nearbyCredential() => NearbyClientCredential(
  desktopId: encodeBytes(List<int>.filled(16, 1)),
  tokenId: encodeBytes(List<int>.filled(16, 3)),
  clientId: encodeBytes(List<int>.filled(16, 4)),
  clientName: 'Milo',
  endpoint: LanEndpoint(
    address: LanIpv4Address.parse('192.168.1.20'),
    port: 9443,
  ),
  certificateSha256: List<int>.filled(32, 5),
  secret: List<int>.filled(32, 6),
);

Future<void> _setView(
  WidgetTester tester,
  Size size, {
  FakeViewPadding viewInsets = FakeViewPadding.zero,
  FakeViewPadding padding = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = viewInsets;
  tester.view.padding = padding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
}

Widget _scaledApp(
  Widget child, {
  double textScale = 2,
  GlobalKey? captureKey,
}) => RepaintBoundary(
  key: captureKey,
  child: MaterialApp(
    theme: meowWatchTheme(),
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: widget!,
    ),
    home: Scaffold(body: child),
  ),
);

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('RENDER_UI')) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.local/visual-review');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
