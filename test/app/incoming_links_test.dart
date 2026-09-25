import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/incoming_links.dart';

void main() {
  test('delivers the cold link before queued warm links', () async {
    final initial = Completer<Uri?>();
    final source = _FakeIncomingLinkSource(initial.future);
    final links = IncomingLinks(source);
    final received = <Uri>[];

    final starting = links.start(
      onLink: received.add,
      onError: (error) => fail('unexpected error: $error'),
    );
    final cold = Uri.parse(
      'meowwatch://join?room=cold&server=syncplay.pl&port=8995',
    );
    final warm = Uri.parse(
      'meowwatch://join?room=warm&server=syncplay.pl&port=8995',
    );
    source.controller.add(warm);
    initial.complete(cold);
    await starting;
    await pumpEventQueue();

    expect(received, [cold, warm]);
    await links.dispose();
    await source.controller.close();
  });

  test(
    'forwards source failures and cancels warm delivery on dispose',
    () async {
      final source = _FakeIncomingLinkSource(Future<Uri?>.value());
      final links = IncomingLinks(source);
      final errors = <Object>[];
      final received = <Uri>[];

      await links.start(onLink: received.add, onError: errors.add);
      source.controller.addError(StateError('platform link failure'));
      await pumpEventQueue();
      expect(errors.single, isA<StateError>());

      await links.dispose();
      expect(source.controller.hasListener, isFalse);
      await source.controller.close();
      expect(received, isEmpty);
    },
  );
}

final class _FakeIncomingLinkSource implements IncomingLinkSource {
  _FakeIncomingLinkSource(this.initial);

  final Future<Uri?> initial;
  final StreamController<Uri> controller = StreamController<Uri>();

  @override
  Future<Uri?> getInitialLink() => initial;

  @override
  Stream<Uri> get uriLinkStream => controller.stream;
}
