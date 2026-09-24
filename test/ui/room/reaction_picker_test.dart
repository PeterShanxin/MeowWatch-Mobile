import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';
import 'package:meowwatch_mobile/core/chat/reaction_catalog.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';

import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

class _Billing extends UiTestBilling {
  void update(bool value) {
    plus = value;
    notifyListeners();
  }
}

class _Client extends SyncplayClient {
  final sent = <String>[];

  void receiveReaction(String emoji) =>
      emitChat(ChatMessage(username: 'Friend', text: encodeReaction(emoji)));

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
    return null;
  }

  @override
  void sendChat(String text) => sent.add(text);

  @override
  Future<void> disposeBackend() async {}
}

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

  late AppController app;
  late _Billing billing;
  late _Client client;
  late SyncTestTarget player;
  var upgrades = 0;
  setUp(() {
    billing = _Billing();
    client = _Client();
    player = SyncTestTarget();
    upgrades = 0;
    app = AppController(
      repository: UiTestRepository(),
      billing: billing,
      hosting: UiTestHosting(),
      phone: player,
      endpointSettings: MemoryEndpointSettings(),
      createSyncClient: () => client,
    );
  });
  tearDown(() => app.close());

  Future<void> openRoom(WidgetTester tester, {double textScale = 1}) async {
    final connected = await tester.runAsync(
      () => app.connect(
        const RoomTicket(
          id: 'reaction-room',
          isHost: false,
          config: RoomConfig(
            server: 'syncplay.pl',
            port: 8995,
            room: 'Movie night',
            username: 'Mochi',
          ),
        ),
      ),
    );
    expect(connected, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowWatchTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: app,
          builder: (_, _) => RoomScreen(
            app: app,
            onLoad: () {},
            onInvite: () {},
            onDevices: () {},
            onLeave: () {},
            onStartRoom: () {},
            onTogglePlay: () {},
            onSeek: (_) {},
            onUpgrade: () => upgrades++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    player.commands.clear();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Send a reaction'));
    await tester.pumpAndSettle();
  }

  Future<void> tapReaction(WidgetTester tester, String emoji) async {
    final button = find.byKey(ValueKey('reaction-$emoji'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  test('all original choices stay free and the new pack is distinct', () {
    expect(standardReactions, ['❤️', '😂', '😮', '👏', '🍿', '🥰']);
    expect(movieNightReactions.toSet(), hasLength(6));
    expect(premiumReactions.intersection(standardReactions.toSet()), isEmpty);
    expect(isPremiumReaction('🦊'), isFalse);
  });

  testWidgets(
    'free account sends each standard choice through the chat protocol',
    (tester) async {
      await openRoom(tester);
      for (final emoji in standardReactions) {
        await openPicker(tester);
        await tapReaction(tester, emoji);
      }
      expect(client.sent, standardReactions.map(encodeReaction).toList());
      expect(upgrades, 0);
      expect(player.commands, isEmpty);
    },
  );

  for (final action in ['emoji', 'unlock button']) {
    testWidgets(
      'locked $action opens upgrade without sending or playback retry',
      (tester) async {
        await openRoom(tester);
        await openPicker(tester);
        expect(find.text('Movie night · Plus'), findsOneWidget);
        if (action == 'emoji') {
          await tapReaction(tester, '🐱');
        } else {
          await tester.ensureVisible(find.text('Unlock with Plus'));
          await tester.tap(find.text('Unlock with Plus'));
          await tester.pumpAndSettle();
        }
        expect(upgrades, 1);
        expect(client.sent, isEmpty);
        expect(player.commands, isEmpty);
        expect(app.needsPlus, isFalse);
        expect(find.text('Movie night · Plus'), findsNothing);
      },
    );
  }

  testWidgets('Plus sends each Movie night choice without a new protocol', (
    tester,
  ) async {
    billing.update(true);
    await openRoom(tester);
    for (final emoji in movieNightReactions) {
      await openPicker(tester);
      expect(find.text('Unlock with Plus'), findsNothing);
      await tapReaction(tester, emoji);
    }
    expect(client.sent, movieNightReactions.map(encodeReaction).toList());
    expect(upgrades, 0);
  });

  testWidgets('revocation before a rebuild still prevents a premium send', (
    tester,
  ) async {
    billing.update(true);
    await openRoom(tester);
    await openPicker(tester);
    billing.update(false);
    await tester.tap(find.byKey(const ValueKey('reaction-🐱')));
    await tester.pumpAndSettle();
    expect(client.sent, isEmpty);
    expect(upgrades, 1);
    expect(app.needsPlus, isFalse);
  });

  testWidgets('entitlement activation updates an already open picker', (
    tester,
  ) async {
    await openRoom(tester);
    await openPicker(tester);
    billing.update(true);
    await tester.pumpAndSettle();
    expect(find.text('Unlock with Plus'), findsNothing);
    await tapReaction(tester, '🐱');
    expect(client.sent, [encodeReaction('🐱')]);
    expect(upgrades, 0);
  });

  testWidgets(
    'free account still receives peer reactions outside the catalog',
    (tester) async {
      await openRoom(tester);
      await tester.runAsync(() async {
        client.receiveReaction('🦊');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(app.reaction?.emoji, '🦊');
      expect(find.text('🦊'), findsOneWidget);
      expect(app.needsPlus, isFalse);
    },
  );

  testWidgets(
    'tablet reaction fits the visible player before and during chat',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await openRoom(tester, textScale: 2);
      player.emit(
        PlaybackSnapshot(
          media: MediaItem(
            uri: Uri.parse('https://example.test/bee.mp4'),
            title: 'Bee.mp4',
          ),
          duration: const Duration(seconds: 90),
          connection: PlaybackConnection.ready,
        ),
      );
      await tester.runAsync(() async {
        client.receiveReaction('🦊');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(player.snapshot.ready, isTrue);
      final reaction = find.byKey(const ValueKey('active-room-reaction'));
      final stage = find
          .ancestor(of: reaction, matching: find.byType(ClipRRect))
          .first;
      final playerList = find
          .ancestor(of: stage, matching: find.byType(ListView))
          .first;
      void expectVisibleStage() {
        final stageRect = tester.getRect(stage);
        final listRect = tester.getRect(playerList);
        final reactionRect = tester.getRect(reaction);
        expect(stageRect.top, greaterThanOrEqualTo(listRect.top));
        expect(stageRect.bottom, lessThanOrEqualTo(listRect.bottom + .01));
        expect(reactionRect.top, greaterThanOrEqualTo(stageRect.top - .01));
        expect(reactionRect.bottom, lessThanOrEqualTo(stageRect.bottom + .01));
        expect(reactionRect.left, greaterThanOrEqualTo(stageRect.left - .01));
        expect(reactionRect.right, lessThanOrEqualTo(stageRect.right + .01));
      }

      expectVisibleStage();
      final stageHeight = tester.getSize(stage).height;
      final chatState = tester.state(find.byType(ChatPanel));
      tester.view.viewInsets = const FakeViewPadding(bottom: 370);
      await tester.pump();
      expect(find.byType(ChatPanel), findsOneWidget);
      expect(tester.state(find.byType(ChatPanel)), same(chatState));
      expectVisibleStage();
      expect(tester.getSize(stage).height, lessThan(stageHeight));
      expect(
        tester.widget<Text>(find.text('🦊')).textScaler,
        TextScaler.noScaling,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 640), const Size(800, 360)]) {
    testWidgets('$size at 200% text can scroll to every reaction and upgrade', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openRoom(tester, textScale: 2);
      await openPicker(tester);
      for (final emoji in [...standardReactions, ...movieNightReactions]) {
        final button = find.byKey(ValueKey('reaction-$emoji'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Unlock with Plus'));
      await tester.tap(find.text('Unlock with Plus'));
      await tester.pumpAndSettle();
      expect(upgrades, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
