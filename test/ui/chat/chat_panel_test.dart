import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';

import '../../app/app_controller_test.dart' as support;
import '../../support/sync_playback_fakes.dart';
import '../home/ui_test_support.dart';

class _Client extends support.ControlledClient {
  final sent = <String>[];
  void receive(ChatMessage message) => emitChat(message);
  @override
  void sendChat(String text) => sent.add(text);
}

class _ChatApp extends AppController {
  _ChatApp(this.client)
    : super(
        repository: UiTestRepository(),
        billing: UiTestBilling(),
        hosting: UiTestHosting(),
        phone: SyncTestTarget(),
        endpointSettings: MemoryEndpointSettings(),
        createSyncClient: () => client,
      );

  final _Client client;
  bool nearbyMode = false;
  bool castingMode = false;
  int loads = 0;
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
    await app.close();
  });

  Future<void> show(
    WidgetTester tester,
    String message, {
    String from = 'Guest',
  }) async {
    await tester.runAsync(() => app.connect(support.ticket));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatPanel(app: app)),
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
