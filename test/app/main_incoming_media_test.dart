import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/incoming_links.dart';
import 'package:meowwatch_mobile/app/incoming_media.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/main.dart';

import '../ui/home/ui_test_support.dart';

void main() {
  testWidgets('cold media waits for onboarding and approval before loading', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    final source = _FakeIncomingMediaSource([
      [_networkProposal('cold', 'https://video.example/cold.mp4')],
    ]);

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingMediaSource: source),
    );
    await _pumpRoute(tester);

    expect(find.byKey(const Key('onboarding-continue-button')), findsOneWidget);
    expect(find.text('Open shared video?'), findsNothing);
    expect(fixture.controller.target.snapshot.media, isNull);

    await tester.enterText(find.byKey(const Key('display-name-field')), 'Milo');
    await tester.ensureVisible(
      find.byKey(const Key('onboarding-continue-button')),
    );
    await tester.tap(find.byKey(const Key('onboarding-continue-button')));
    await _pumpRoute(tester);

    expect(find.text('Open shared video?'), findsOneWidget);
    expect(find.text('cold.mp4'), findsOneWidget);
    expect(fixture.controller.target.snapshot.media, isNull);
    await tester.tap(find.text('Cancel'));
    await _pumpRoute(tester);
    expect(fixture.controller.target.snapshot.media, isNull);

    await _dispose(tester, fixture, source);
  });

  testWidgets('cancel keeps the current room and media unchanged', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    await fixture.controller.useLocalMode();
    final currentMedia = MediaItem.fromUrl('https://video.example/current.mp4');
    await fixture.controller.load(currentMedia);
    const currentRoom = RoomTicket(
      id: 'current-room-ticket',
      isHost: false,
      config: RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'current-room',
        username: 'Milo',
      ),
    );
    fixture.controller.room = currentRoom;
    final source = _FakeIncomingMediaSource([
      [_networkProposal('replacement', 'https://video.example/new.mp4')],
    ]);

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingMediaSource: source),
    );
    await _pumpRoute(tester);

    expect(find.text('Open shared video?'), findsOneWidget);
    expect(
      find.textContaining('Replace your video in the current room'),
      findsOneWidget,
    );
    expect(fixture.controller.target.snapshot.media, same(currentMedia));
    expect(fixture.controller.room, same(currentRoom));

    await tester.tap(find.text('Cancel'));
    await _pumpRoute(tester);

    expect(fixture.controller.target.snapshot.media, same(currentMedia));
    expect(fixture.controller.room, same(currentRoom));
    expect(fixture.controller.target.snapshot.playing, isFalse);

    fixture.controller.room = null;
    await _dispose(tester, fixture, source);
  });

  testWidgets('approved URL opens on this phone and remains paused', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final source = _FakeIncomingMediaSource([
      [_networkProposal('approved', 'https://video.example/approved.mp4')],
    ]);

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingMediaSource: source),
    );
    await _pumpRoute(tester);

    expect(fixture.controller.target.snapshot.media, isNull);
    await tester.tap(find.byKey(const Key('confirm-shared-video-button')));
    await _pumpRoute(tester);

    final snapshot = fixture.controller.target.snapshot;
    expect(
      snapshot.media?.uri,
      Uri.parse('https://video.example/approved.mp4'),
    );
    expect(snapshot.ready, isTrue);
    expect(snapshot.playing, isFalse);
    expect(fixture.controller.inPlayer, isTrue);
    expect(fixture.controller.room, isNull);

    await _dispose(tester, fixture, source);
  });

  testWidgets(
    'warm temporary content warns and never enters Continue Watching',
    (tester) async {
      final fixture = UiTestApp.create();
      await fixture.controller.setName('Milo');
      final source = _FakeIncomingMediaSource([const []]);

      await tester.pumpWidget(
        MainApp(controller: fixture.controller, incomingMediaSource: source),
      );
      await _pumpRoute(tester);
      expect(find.byKey(const Key('home-scroll-view')), findsOneWidget);

      source.emit([
        IncomingMedia.fromPlatform({
          'id': 'temporary-content',
          'kind': 'media',
          'uri': 'content://documents.example/shared-video',
          'mimeType': 'video/mp4',
          'readAccess': true,
          'durableAccess': false,
        }),
      ]);
      await _pumpRoute(tester);

      expect(find.text('Open shared video?'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('temporary video access'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Continue Watching'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm-shared-video-button')));
      await _pumpRoute(tester);
      await fixture.controller.saveProgress();

      expect(fixture.controller.target.snapshot.media?.canRemember, isFalse);
      expect(fixture.controller.target.snapshot.playing, isFalse);
      expect(fixture.repository.history, isEmpty);

      await _dispose(tester, fixture, source);
    },
  );

  testWidgets('multiple proposals are reviewed one at a time', (tester) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final source = _FakeIncomingMediaSource([
      [
        _networkProposal('first', 'https://video.example/first.mp4'),
        _networkProposal('second', 'https://video.example/second.mp4'),
      ],
    ]);

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingMediaSource: source),
    );
    await _pumpRoute(tester);

    expect(find.text('Open shared video?'), findsOneWidget);
    expect(find.text('first.mp4'), findsOneWidget);
    expect(find.text('second.mp4'), findsNothing);
    expect(fixture.controller.target.snapshot.media, isNull);

    await tester.tap(find.text('Cancel'));
    await _pumpRoute(tester);

    expect(find.text('Open shared video?'), findsOneWidget);
    expect(find.text('first.mp4'), findsNothing);
    expect(find.text('second.mp4'), findsOneWidget);
    expect(fixture.controller.target.snapshot.media, isNull);
    await tester.tap(find.byKey(const Key('confirm-shared-video-button')));
    await _pumpRoute(tester);
    expect(
      fixture.controller.target.snapshot.media?.uri,
      Uri.parse('https://video.example/second.mp4'),
    );

    await _dispose(tester, fixture, source);
  });

  testWidgets('HTTPS VIEW from both bridges opens one media review', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final uri = Uri.parse('https://video.example/shared.mp4');
    final mediaSource = _FakeIncomingMediaSource([
      [_networkProposal('shared-view', uri.toString())],
    ]);
    final linkSource = _FakeIncomingLinkSource(uri);

    await tester.pumpWidget(
      MainApp(
        controller: fixture.controller,
        incomingLinkSource: linkSource,
        incomingMediaSource: mediaSource,
      ),
    );
    await _pumpRoute(tester);

    expect(find.text('Open shared video?'), findsOneWidget);
    expect(find.text('shared.mp4'), findsOneWidget);
    expect(
      find.textContaining('Could not open that room invitation.'),
      findsNothing,
    );
    expect(fixture.controller.target.snapshot.media, isNull);

    await tester.tap(find.text('Cancel'));
    await _pumpRoute(tester);
    expect(find.text('Open shared video?'), findsNothing);

    await _dispose(tester, fixture, mediaSource, linkSource: linkSource);
  });
}

IncomingMedia _networkProposal(String id, String uri) =>
    IncomingMedia.fromPlatform({
      'id': id,
      'kind': 'media',
      'uri': uri,
      'mimeType': 'video/mp4',
    });

Future<void> _pumpRoute(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _dispose(
  WidgetTester tester,
  UiTestApp fixture,
  _FakeIncomingMediaSource source, {
  _FakeIncomingLinkSource? linkSource,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await fixture.close();
    await source.close();
    await linkSource?.close();
  });
}

final class _FakeIncomingMediaSource implements IncomingMediaSource {
  _FakeIncomingMediaSource(List<List<IncomingMedia>> initial)
    : _batches = List<List<IncomingMedia>>.from(initial);

  final List<List<IncomingMedia>> _batches;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<IncomingMedia>> takePending() async =>
      _batches.isEmpty ? const [] : _batches.removeAt(0);

  void emit(List<IncomingMedia> batch) {
    _batches.add(batch);
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
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
