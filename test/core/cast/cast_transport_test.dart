import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/cast/cast_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shared platform event subscription survives retiring an older target',
    () async {
      const channel = MethodChannel('com.meowwatch.mobile/cast/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final first = <Map<Object?, Object?>>[];
      final second = <Map<Object?, Object?>>[];
      final oldSubscription = AndroidCastTransport().events.listen(first.add);
      final newSubscription = AndroidCastTransport().events.listen(second.add);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['listen']);

      Future<void> send(int revision) => messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'revision': revision,
        }),
        (_) {},
      );

      await send(1);
      await Future<void>.delayed(Duration.zero);
      expect(first.single['revision'], 1);
      expect(second.single['revision'], 1);
      await oldSubscription.cancel();
      expect(calls, ['listen']);
      await send(2);
      await Future<void>.delayed(Duration.zero);
      expect(first, hasLength(1));
      expect(second.last['revision'], 2);
      await newSubscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['listen', 'cancel']);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
