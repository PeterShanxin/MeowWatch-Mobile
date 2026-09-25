import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_desktop_target.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_snapshot.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/nearby/nearby_devices_sheet.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';

import '../home/ui_test_support.dart';

void main() {
  testWidgets('shows a real loading state and fits a narrow large-text sheet', (
    tester,
  ) async {
    await _setView(tester, const Size(320, 600));
    final fixture = UiTestApp.create();
    final backend = FakeNearbyBackend()..savedGate = Completer();

    await tester.pumpWidget(
      _app(
        NearbyDevicesSheet(app: fixture.controller, backend: backend),
        textScale: 2,
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading nearby devices'), findsOneWidget);
    expect(tester.takeException(), isNull);

    backend.savedGate!.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('This phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
    expect(backend.disposed, isTrue);
  });

  testWidgets('permission failure stays visible beside saved pairings', (
    tester,
  ) async {
    await _setView(tester, const Size(600, 720));
    final fixture = UiTestApp.create();
    final credential = _credential(1);
    final backend = FakeNearbyBackend()
      ..saved = [credential]
      ..startError = const NearbyPlatformException('permission_denied');

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Allow local network access'), findsOneWidget);
    expect(find.text('Paired desktop'), findsOneWidget);
    expect(
      find.text('Saved pairing · connect using its verified address'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('current desktop loses verified status when it disconnects', (
    tester,
  ) async {
    await _setView(tester, const Size(500, 720));
    final fixture = UiTestApp.create();
    final desktop = _SheetDesktop(_credential(4));
    final backend = FakeNearbyBackend();
    expect(await fixture.controller.adoptNearby(desktop), isTrue);

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Connected and verified · controlling desktop playback'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Cinema desktop'),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    desktop.disconnect();
    await tester.pump();

    expect(fixture.controller.isNearby, isTrue);
    expect(
      find.text('Desktop disconnected · reconnect or watch on this phone'),
      findsOneWidget,
    );
    expect(
      find.text('Connected and verified · controlling desktop playback'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Cinema desktop'),
        matching: find.byIcon(Icons.link_off_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Cinema desktop'),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'This phone'))
          .onTap,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('invalid pasted invitation is rejected before the backend', (
    tester,
  ) async {
    await _setView(tester, const Size(420, 760));
    final fixture = UiTestApp.create();
    final backend = FakeNearbyBackend();

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paste-nearby-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nearby-invitation-field')),
      'not-a-pairing-invitation',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('invitation is not valid'), findsOneWidget);
    expect(backend.pairCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('discovery name labels a matching saved pairing only', (
    tester,
  ) async {
    await _setView(tester, const Size(500, 720));
    final fixture = UiTestApp.create();
    final credential = _credential(7);
    final backend = FakeNearbyBackend()..saved = [credential];

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    backend.controller.add(
      NearbyDiscoveryEvent(
        NearbyAdvertisement(
          desktopId: credential.desktopId,
          displayName: 'Cinema desktop',
          pairingOpen: false,
          port: 9443,
          addressHints: const ['192.168.1.44'],
        ),
        NearbyMdnsStatus.found,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cinema desktop'), findsOneWidget);
    expect(
      find.text('Found nearby · saved pairing verified on connect'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('pairing exposes desktop approval and supports cancellation', (
    tester,
  ) async {
    await _setView(tester, const Size(420, 760));
    final fixture = UiTestApp.create();
    final backend = FakeNearbyBackend()..holdPairing = true;

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    await _pasteInvitation(tester, _invitation().encodeQr());
    await tester.pump();

    expect(
      find.text('Approve this phone on your desktop to finish pairing.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel pairing'));
    await tester.pumpAndSettle();
    expect(backend.cancelCalls, 1);
    expect(find.text('Cancel pairing'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('offline removal clearly stays local to this phone', (
    tester,
  ) async {
    await _setView(tester, const Size(500, 720));
    final fixture = UiTestApp.create();
    final credential = _credential(9);
    final backend = FakeNearbyBackend()..saved = [credential];

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove saved pairing'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from this phone?'), findsOneWidget);
    expect(
      find.textContaining('saved pairing only from this phone'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(backend.removed, [credential.desktopId]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });

  testWidgets('desktop denial is actionable and does not claim pairing', (
    tester,
  ) async {
    await _setView(tester, const Size(420, 760));
    final fixture = UiTestApp.create();
    final backend = FakeNearbyBackend()
      ..pairError = const NearbyException('approval_denied');

    await tester.pumpWidget(
      _app(NearbyDevicesSheet(app: fixture.controller, backend: backend)),
    );
    await tester.pumpAndSettle();
    await _pasteInvitation(tester, _invitation().encodeQr());
    await tester.pumpAndSettle();

    expect(
      find.text('The desktop declined this pairing request.'),
      findsOneWidget,
    );
    expect(backend.pairCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.close);
  });
}

class _SheetDesktop extends NearbyDesktopTarget {
  _SheetDesktop(NearbyClientCredential credential)
    : _remote = NearbySnapshot(
        desktopId: credential.desktopId,
        desktopName: 'Cinema desktop',
        epoch: 'test-epoch',
        username: 'Milo',
        connection: SyncConnectionStatus.connected,
        playback: const PlaybackSnapshot(),
        participants: const {},
        messages: const [],
      ),
      super(
        client: NearbyClient(store: _MemoryClientStore()),
        credential: credential,
      );

  final NearbySnapshot _remote;
  bool _connected = true;

  @override
  NearbySnapshot get remote => _remote;
  @override
  String get label => _remote.desktopName;
  @override
  bool get connected => _connected;

  void disconnect() {
    _connected = false;
    notifyListeners();
  }
}

class _MemoryClientStore implements NearbyClientStore {
  @override
  Future<NearbyClientCredential?> read(String desktopId) async => null;
  @override
  Future<void> remove(String desktopId) async {}
  @override
  Future<void> write(NearbyClientCredential credential) async {}
}

class FakeNearbyBackend implements NearbyDevicesBackend {
  final controller = StreamController<NearbyDiscoveryEvent>.broadcast();
  List<NearbyClientCredential> saved = const [];
  Completer<List<NearbyClientCredential>>? savedGate;
  Object? startError;
  Object? pairError;
  bool holdPairing = false;
  Completer<NearbyDesktopTarget>? pairGate;
  int pairCalls = 0;
  int cancelCalls = 0;
  final List<String> removed = [];
  bool disposed = false;

  @override
  Stream<NearbyDiscoveryEvent> get discoveries => controller.stream;
  @override
  Future<List<NearbyClientCredential>> loadSaved() async =>
      savedGate == null ? saved : savedGate!.future;
  @override
  Future<void> startDiscovery() async {
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<NearbyDesktopTarget> connect(
    NearbyClientCredential credential, {
    NearbyAdvertisement? advertisement,
  }) => throw UnimplementedError();

  @override
  Future<NearbyDesktopTarget> pair(
    PairingInvitation invitation, {
    required String clientName,
    required ValueChanged<NearbyClientState> onState,
  }) async {
    pairCalls++;
    onState(const NearbyClientState(NearbyClientPhase.awaitingApproval));
    if (pairError != null) throw pairError!;
    if (holdPairing) {
      pairGate = Completer<NearbyDesktopTarget>();
      return pairGate!.future;
    }
    throw UnimplementedError();
  }

  @override
  Future<void> cancelPairing() async {
    cancelCalls++;
    if (pairGate?.isCompleted == false) {
      pairGate!.completeError(const NearbyException('cancelled'));
    }
  }

  @override
  Future<void> remove(String desktopId) async {
    removed.add(desktopId);
    saved = saved.where((item) => item.desktopId != desktopId).toList();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await cancelPairing();
    await controller.close();
  }
}

NearbyClientCredential _credential(int seed) => NearbyClientCredential(
  desktopId: encodeBytes(List<int>.filled(16, seed)),
  tokenId: encodeBytes(List<int>.filled(16, seed + 1)),
  clientId: encodeBytes(List<int>.filled(16, seed + 2)),
  clientName: 'Milo',
  endpoint: LanEndpoint(
    address: LanIpv4Address.parse('192.168.1.${seed + 20}'),
    port: 9443,
  ),
  certificateSha256: List<int>.filled(32, seed + 3),
  secret: List<int>.filled(32, seed + 4),
);

PairingInvitation _invitation() => PairingInvitation(
  desktopId: encodeBytes(List<int>.filled(16, 10)),
  pairId: encodeBytes(List<int>.filled(16, 11)),
  endpoint: LanEndpoint(
    address: LanIpv4Address.parse('192.168.1.30'),
    port: 9443,
  ),
  certificateSha256: List<int>.filled(32, 12),
  pairSecret: List<int>.filled(16, 13),
);

Future<void> _pasteInvitation(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const Key('paste-nearby-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('nearby-invitation-field')),
    value,
  );
  await tester.tap(find.text('Continue'));
}

Future<void> _setView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: meowWatchTheme(),
  builder: (context, widget) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: widget!,
  ),
  home: Scaffold(body: child),
);
