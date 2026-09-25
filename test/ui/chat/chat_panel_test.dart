import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';

import '../../app/app_controller_test.dart' as support;
import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

class _Client extends support.ControlledClient {
  final sent = <String>[];
  void receive(ChatMessage message) => emitChat(message);
  @override
  void sendChat(String text) => sent.add(text);
}

class _ChatTarget extends SyncTestTarget {
  @override
  void emit(PlaybackSnapshot value) {
    super.emit(value);
    notifyListeners();
  }

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    try {
      await super.load(media, position: position);
    } catch (_) {
      emit(
        PlaybackSnapshot(
          media: media,
          connection: PlaybackConnection.failed,
          error: 'This video could not be opened.',
        ),
      );
      rethrow;
    }
  }
}

class _ChatApp extends AppController {
  _ChatApp(this.client)
    : super(
        repository: UiTestRepository(),
        billing: UiTestBilling(),
        hosting: UiTestHosting(),
        phone: _ChatTarget(),
        endpointSettings: MemoryEndpointSettings(),
        createSyncClient: () => client,
      );

  final _Client client;
  bool nearbyMode = false;
  bool castingMode = false;
  int loads = 0;
  VoidCallback? beforeLoad;
  PlaybackTarget? selectedTarget;
  @override
  PlaybackTarget get target => selectedTarget ?? super.target;
  @override
  bool get isNearby => nearbyMode;
  @override
  bool get isCasting => castingMode;
  @override
  bool get isConnected => connection.status == SyncConnectionStatus.connected;
  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    loads++;
    beforeLoad?.call();
    await super.load(media, position: position);
  }
}

void main() {
  late _ChatApp app;
  late _Client client;
  setUp(() {
    client = _Client();
    app = _ChatApp(client);
  });
  tearDown(() async {
    app.nearbyMode = false;
    app.castingMode = false;
    app.selectedTarget = null;
    app.busy = false;
    await app.close();
  });

  Future<void> show(
    WidgetTester tester,
    String message, {
    String from = 'Guest',
    bool asSheet = false,
    bool inRoom = false,
    VoidCallback? onLoad,
  }) async {
    await tester.runAsync(() => app.connect(support.ticket));
    await tester.pumpWidget(
      MaterialApp(
        home: inRoom
            ? ListenableBuilder(
                listenable: app,
                builder: (context, _) => RoomScreen(
                  app: app,
                  onLoad: onLoad ?? () {},
                  onInvite: () {},
                  onDevices: () {},
                  onLeave: () {},
                  onStartRoom: () {},
                  onTogglePlay: () => unawaited(app.togglePlay()),
                  onSeek: (_) {},
                ),
              )
            : asSheet
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showChatSheet(context, app),
                    child: const Text('Open room chat'),
                  ),
                ),
              )
            : Scaffold(body: ChatPanel(app: app)),
      ),
    );
    await tester.runAsync(() async {
      client.receive(
        ChatMessage(
          username: from == 'Host' ? app.username : from,
          text: message,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    expect(app.messages.last.text, message);
    await tester.pumpAndSettle();
    if (asSheet) {
      await tester.tap(
        inRoom
            ? find.widgetWithText(TextButton, 'Chat')
            : find.text('Open room chat'),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('peer typing changes preserve the focused composer and draft', (
    tester,
  ) async {
    await show(tester, 'Movie night');
    final field = find.byType(TextField);
    await tester.enterText(field, 'Keep my draft');
    final original = tester.state<EditableTextState>(find.byType(EditableText));
    for (final typing in [true, false, true, false]) {
      await tester.runAsync(() async {
        client.receive(
          ChatMessage(username: 'Guest', text: encodeTyping(typing)),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Guest typing…'),
        typing ? findsOneWidget : findsNothing,
      );
      expect(tester.state(find.byType(EditableText)), same(original));
      expect(original.widget.focusNode.hasFocus, isTrue);
      expect(original.widget.controller.text, 'Keep my draft');
      expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.sent, contains('Keep my draft'));
    expect(original.widget.controller.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final layout in [
    (name: 'phone', size: const Size(412, 892), hasPreview: true),
    (name: 'tablet', size: const Size(1280, 800), hasPreview: false),
  ]) {
    testWidgets('${layout.name} chat bubbles are distinct from room previews', (
      tester,
    ) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => app.connect(support.ticket));
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: app,
            builder: (context, _) => RoomScreen(
              app: app,
              onLoad: () {},
              onInvite: () {},
              onDevices: () {},
              onLeave: () {},
              onStartRoom: () {},
              onTogglePlay: () {},
              onSeek: (_) {},
            ),
          ),
        ),
      );

      const received = 'Ready for movie night, Host! 🍿';
      await tester.runAsync(() async {
        client.receive(const ChatMessage(username: 'Guest', text: received));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      if (layout.hasPreview) {
        // Keep the real room preview built behind the phone's chat sheet.
        await tester.ensureVisible(find.text(received));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Chat'));
        await tester.pumpAndSettle();
      }

      void expectBubble(String message) {
        final bubble = find.descendant(
          of: find.byType(ChatPanel),
          matching: find.text(message),
        );
        expect(bubble, findsOneWidget);
        expect(bubble.hitTestable(), findsOneWidget);
        expect(find.text(message), findsNWidgets(layout.hasPreview ? 2 : 1));
        expect(
          app.messages.where((item) => item.text == message),
          hasLength(1),
        );
      }

      expectBubble(received);
      const sent = 'Ready here too. Press play when you are comfy.';
      final composer = find.descendant(
        of: find.byType(ChatPanel),
        matching: find.byType(TextField),
      );
      await tester.enterText(composer, sent);
      await tester.tap(find.byTooltip('Send message').hitTestable());
      expect(client.sent, contains(sent));
      // The server echoes a sent message before it becomes a local bubble.
      await tester.runAsync(() async {
        client.receive(ChatMessage(username: app.username, text: sent));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
      expectBubble(sent);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'peer URL requires review and confirmation, preserving room client',
    (tester) async {
      const link = 'https://video.example/movie.mp4?token=private';
      await show(tester, link);
      expect(app.loads, 0);
      expect(app.target.snapshot.media, isNull);
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      expect(find.text('Video from video.example'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('network address'), findsOneWidget);
      expect(app.loads, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.loads, 0);

      final room = app.room;
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load video'));
      await tester.pumpAndSettle();
      expect(app.loads, 1);
      expect(app.target.snapshot.media?.uri.toString(), link);
      expect(app.target.snapshot.media?.title, 'movie.mp4');
      expect(app.room, same(room));
      expect(app.isConnected, isTrue);
      expect(client.closed, isFalse);
      expect(client.sent, isEmpty); // Loading does not broadcast the URL/token.
    },
  );

  testWidgets(
    'loading after sheet dismissal cannot dismiss a newer route on completion',
    (tester) async {
      const link = 'https://video.example/movie.mp4';
      final loadGate = Completer<void>();
      (app.target as SyncTestTarget).loadGate = loadGate;
      await show(tester, link, asSheet: true);
      final sheetRoute = ModalRoute.of(tester.element(find.byType(ChatPanel)))!;
      final navigator = sheetRoute.navigator!;
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load video'));
      await tester.pumpAndSettle();
      expect(app.loads, 1);
      expect(app.target.snapshot.ready, isFalse);
      expect(sheetRoute.isActive, isFalse);
      expect(find.byType(ChatPanel), findsNothing);
      // Loading now begins after the owned sheet has fully left the tree.
      // Its later completion must still preserve a newly opened route.
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('New room screen')),
          ),
        ),
      );
      loadGate.complete();
      await tester.pumpAndSettle();

      expect(app.target.snapshot.media?.uri.toString(), link);
      expect(app.target.snapshot.ready, isTrue);
      expect(find.byType(ChatPanel), findsNothing);
      expect(find.text('New room screen'), findsOneWidget);
      expect(navigator.canPop(), isTrue);
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: true,
  );

  testWidgets(
    'late Close callback during automatic sheet reversal preserves root route',
    (tester) async {
      const link = 'https://video.example/movie.mp4';
      final loadGate = Completer<void>();
      (app.target as SyncTestTarget).loadGate = loadGate;
      await show(tester, link, asSheet: true);
      final sheetRoute = ModalRoute.of(tester.element(find.byType(ChatPanel)))!;
      final navigator = sheetRoute.navigator!;
      final close = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Close chat',
            ),
          )
          .onPressed!;
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load video'));
      await tester.pump();
      expect(app.loads, 0);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(app.loads, 0);
      expect(sheetRoute.animation!.status, AnimationStatus.reverse);
      expect(sheetRoute.isActive, isFalse);
      expect(find.byType(ChatPanel), findsOneWidget);
      // Deliver the real button's already-captured callback. Flutter ignores
      // fresh pointer hits while reversing, but queued callbacks can be late.
      close();
      await tester.pumpAndSettle();

      expect(app.loads, 1);
      expect(app.target.snapshot.ready, isFalse);
      expect(find.byType(ChatPanel), findsNothing);
      expect(find.text('Open room chat'), findsOneWidget);
      expect(navigator.canPop(), isFalse);
      loadGate.complete();
      await tester.pumpAndSettle();
      expect(app.target.snapshot.ready, isTrue);
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: true,
  );

  for (final asSheet in [false, true]) {
    testWidgets(
      '${asSheet ? 'phone' : 'inline'} load starts after its modals leave the tree',
      (tester) async {
        await show(tester, 'https://video.example/movie.mp4', asSheet: asSheet);
        final panelRoute = ModalRoute.of(
          tester.element(find.byType(ChatPanel)),
        )!;
        app.beforeLoad = () {
          expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
          expect(
            find.byType(ChatPanel, skipOffstage: false),
            asSheet ? findsNothing : findsOneWidget,
          );
          expect(panelRoute.isActive, !asSheet);
        };
        await tester.tap(find.text('Watch this too'));
        await tester.pumpAndSettle();
        final dialogRoute = ModalRoute.of(
          tester.element(find.byType(AlertDialog)),
        )!;
        await tester.tap(find.text('Load video'));
        await tester.pump();
        expect(app.loads, 0);
        expect(dialogRoute.animation!.status, AnimationStatus.reverse);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.pumpAndSettle();
        expect(app.loads, 1);
        expect(app.target.snapshot.ready, isTrue);
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: true,
    );
  }

  testWidgets(
    'cancelling review leaves phone chat open without loading',
    (tester) async {
      await show(tester, 'https://video.example/movie.mp4', asSheet: true);
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.loads, 0);
      expect(find.byType(ChatPanel), findsOneWidget);
      expect(find.text('Watch this too').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Close chat'));
      await tester.pumpAndSettle();
      expect(find.text('Open room chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: true,
  );

  for (final duringSheet in [false, true]) {
    for (final change in [
      'room',
      'target',
      'connection',
      'busy',
      'Nearby',
      'unsupported Cast',
    ]) {
      testWidgets(
        '$change change during ${duringSheet ? 'sheet' : 'dialog'} exit cancels loading',
        (tester) async {
          await show(tester, 'http://video.example/movie.mp4', asSheet: true);
          await tester.tap(find.text('Watch this too'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Load video'));
          await tester.pump();
          if (duringSheet) {
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pump();
          }
          expect(app.loads, 0);
          switch (change) {
            case 'room':
              app.room = null;
            case 'target':
              final replacement = SyncTestTarget();
              app.selectedTarget = replacement;
              addTearDown(replacement.close);
            case 'connection':
              app.connection = const SyncConnectionState(
                status: SyncConnectionStatus.disconnected,
              );
            case 'busy':
              app.busy = true;
            case 'Nearby':
              app.nearbyMode = true;
            case 'unsupported Cast':
              app.castingMode = true;
          }
          await tester.pumpAndSettle();
          expect(app.loads, 0);
          expect(app.phone.snapshot.media, isNull);
          expect(tester.takeException(), isNull);
        },
        semanticsEnabled: true,
      );
    }

    testWidgets(
      'a new route during ${duringSheet ? 'sheet' : 'dialog'} exit cancels loading',
      (tester) async {
        await show(tester, 'https://video.example/movie.mp4', asSheet: true);
        final sheetRoute = ModalRoute.of(
          tester.element(find.byType(ChatPanel)),
        )!;
        final navigator = sheetRoute.navigator!;
        await tester.tap(find.text('Watch this too'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load video'));
        await tester.pump();
        if (duringSheet) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump();
        }
        expect(app.loads, 0);
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('New room screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(app.loads, 0);
        expect(find.text('New room screen'), findsOneWidget);
        expect(navigator.canPop(), isTrue);
        navigator.pop();
        await tester.pumpAndSettle();
        if (!duringSheet) {
          expect(sheetRoute.isCurrent, isTrue);
          await tester.tap(find.byTooltip('Close chat'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Open room chat'), findsOneWidget);
        expect(navigator.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: true,
    );
  }

  testWidgets(
    'replacing the player during owned sheet dismissal cancels loading',
    (tester) async {
      await show(tester, 'https://video.example/movie.mp4', asSheet: true);
      final navigator = Navigator.of(tester.element(find.byType(ChatPanel)));
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(app.loads, 0);
      unawaited(
        navigator.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Replacement screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.loads, 0);
      expect(find.text('Replacement screen'), findsOneWidget);
      expect(find.text('Open room chat', skipOffstage: false), findsNothing);
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: true,
  );

  for (final fails in [false, true]) {
    testWidgets(
      'phone player exposes shared-link ${fails ? 'failure and recovery' : 'loading and success'}',
      (tester) async {
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final loadGate = Completer<void>();
        (app.phone as SyncTestTarget).loadGate = loadGate;
        const recoveryLink = 'https://video.example/recovery.mp4';
        await show(
          tester,
          'https://video.example/movie.mp4',
          asSheet: true,
          inRoom: true,
          onLoad: () => unawaited(app.load(MediaItem.fromUrl(recoveryLink))),
        );
        await tester.tap(find.text('Watch this too'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load video'));
        await tester.pump();
        expect(app.loads, 0);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(app.loads, 0);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(app.loads, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(ChatPanel), findsNothing);
        expect(find.text('Opening your video…').hitTestable(), findsOneWidget);
        if (fails) {
          loadGate.completeError(StateError('video unavailable'));
        } else {
          loadGate.complete();
        }
        await tester.pumpAndSettle();
        if (fails) {
          expect(
            find.text('This video could not be opened.').hitTestable(),
            findsOneWidget,
          );
          final recovery = find.text('Choose another video').hitTestable();
          expect(recovery, findsOneWidget);
          await tester.tap(recovery);
          await tester.pumpAndSettle();
          expect(app.loads, 2);
          expect(app.target.snapshot.media?.uri.toString(), recoveryLink);
          expect(find.text('This video could not be opened.'), findsNothing);
        }
        expect(app.target.snapshot.ready, isTrue);
        expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
        expect(find.byType(ChatPanel), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      semanticsEnabled: true,
    );
  }

  testWidgets(
    'own messages, normal text and multi-URL messages have no action',
    (tester) async {
      await show(tester, 'https://video.example/movie.mp4', from: 'Host');
      await tester.runAsync(() async {
        client.receive(const ChatMessage(username: 'Guest', text: 'hello'));
        client.receive(
          const ChatMessage(
            username: 'Guest',
            text: 'https://a.example/a.mp4 https://b.example/b.mp4',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(app.messages.length, 3);
      expect(find.text('Watch this too'), findsNothing);
      expect(app.loads, 0);
    },
  );

  testWidgets('HTTP disclosure and unsupported Cast provide phone recovery', (
    tester,
  ) async {
    await show(tester, 'http://video.example/movie.mp4');
    app.castingMode = true;
    await tester.tap(find.text('Watch this too'));
    await tester.pumpAndSettle();
    expect(find.text('This HTTP link is not encrypted.'), findsOneWidget);
    expect(find.textContaining('Return to This phone'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Load video'))
          .onPressed,
      isNull,
    );
    expect(app.loads, 0);
  });

  testWidgets(
    'Nearby explains desktop selection without sending load commands',
    (tester) async {
      await show(tester, 'https://video.example/movie.mp4');
      app.nearbyMode = true;
      await tester.tap(find.text('Watch this too'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Choose this link on your desktop'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Load video'),
            )
            .onPressed,
        isNull,
      );
      expect(app.loads, 0);
    },
  );

  testWidgets('leaving while review is open invalidates confirmation', (
    tester,
  ) async {
    await show(tester, 'https://video.example/movie.mp4');
    await tester.tap(find.text('Watch this too'));
    await tester.pumpAndSettle();
    await tester.runAsync(app.useLocalMode);
    await tester.pumpAndSettle();
    expect(find.textContaining('Your room or screen changed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Load video'))
          .onPressed,
      isNull,
    );
    expect(app.loads, 0);
  });

  testWidgets('shared link review fits a small phone at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, 'https://video.example/movie.mp4');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: ChatPanel(app: app)),
      ),
    );
    await tester.tap(find.text('Watch this too'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Load video'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.loads, 0);
    expect(tester.takeException(), isNull);
  });
}
