import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/incoming_links.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/main.dart';

import '../ui/home/ui_test_support.dart';

const invite = 'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995';

void main() {
  testWidgets('cold invite opens a prefilled review without joining', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final source = _FakeIncomingLinkSource(Uri.parse(invite));

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingLinkSource: source),
    );
    await _pumpRoute(tester);

    expect(find.text('Room invitation received'), findsOneWidget);
    expect(find.text('Room: quiet-otter'), findsOneWidget);
    expect(find.text('Server: syncplay.pl:8995'), findsOneWidget);
    expect(find.text('Join this room'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('join-code-field')),
    );
    expect(field.controller?.text, invite);
    expect(fixture.controller.room, isNull);

    await _dispose(tester, fixture, source);
  });

  testWidgets('cold invite waits for onboarding completion', (tester) async {
    final fixture = UiTestApp.create();
    final source = _FakeIncomingLinkSource(Uri.parse(invite));

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingLinkSource: source),
    );
    await _pumpRoute(tester);
    expect(find.byKey(const Key('onboarding-continue-button')), findsOneWidget);
    expect(find.text('Room invitation received'), findsNothing);

    await fixture.controller.setName('Milo');
    await _pumpRoute(tester);
    expect(find.text('Room invitation received'), findsOneWidget);
    expect(fixture.controller.room, isNull);

    await _dispose(tester, fixture, source);
  });

  testWidgets('duplicate warm invite keeps a single confirmation sheet', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final source = _FakeIncomingLinkSource(null);

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingLinkSource: source),
    );
    await _pumpRoute(tester);
    source.controller.add(Uri.parse(invite));
    source.controller.add(Uri.parse(invite));
    await _pumpRoute(tester);

    expect(find.text('Room invitation received'), findsOneWidget);
    expect(find.byKey(const Key('join-code-field')), findsOneWidget);
    expect(fixture.controller.room, isNull);

    await _dispose(tester, fixture, source);
  });

  testWidgets('active room requires explicit leave intent before review', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    fixture.controller.room = const RoomTicket(
      id: 'active-room',
      isHost: false,
      config: RoomConfig(
        server: 'syncplay.pl',
        port: 8995,
        room: 'current-room',
        username: 'Milo',
      ),
    );
    final source = _FakeIncomingLinkSource(Uri.parse(invite));

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingLinkSource: source),
    );
    await _pumpRoute(tester);

    expect(find.text('Leave current room?'), findsOneWidget);
    expect(find.text('Stay in current room'), findsOneWidget);
    expect(find.text('Room invitation received'), findsNothing);
    await tester.tap(find.text('Stay in current room'));
    await _pumpRoute(tester);
    expect(fixture.controller.room?.config.room, 'current-room');
    expect(find.text('Room invitation received'), findsNothing);

    fixture.controller.room = null;
    await _dispose(tester, fixture, source);
  });

  testWidgets('malformed invite shows a helpful error and no join sheet', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    await fixture.controller.setName('Milo');
    final source = _FakeIncomingLinkSource(
      Uri.parse('meowwatch://join?room=quiet-otter&server=x&port=99999'),
    );

    await tester.pumpWidget(
      MainApp(controller: fixture.controller, incomingLinkSource: source),
    );
    await _pumpRoute(tester);

    expect(
      find.textContaining('Could not open that room invitation.'),
      findsOneWidget,
    );
    expect(find.text('Room invitation received'), findsNothing);
    expect(fixture.controller.room, isNull);

    await _dispose(tester, fixture, source);
  });
}

Future<void> _pumpRoute(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _dispose(
  WidgetTester tester,
  UiTestApp fixture,
  _FakeIncomingLinkSource source,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await fixture.close();
    await source.close();
  });
}

final class _FakeIncomingLinkSource implements IncomingLinkSource {
  _FakeIncomingLinkSource(Uri? initial)
    : _initial = Future<Uri?>.value(initial);

  final Future<Uri?> _initial;
  final StreamController<Uri> controller = StreamController<Uri>();

  @override
  Future<Uri?> getInitialLink() => _initial;

  @override
  Stream<Uri> get uriLinkStream => controller.stream;

  Future<void> close() => controller.close();
}
