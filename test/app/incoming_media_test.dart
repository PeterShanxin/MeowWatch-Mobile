import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/incoming_media.dart';

Map<Object?, Object?> proposal(String uri, {String id = 'one', String? mime}) =>
    {'id': id, 'kind': 'media', 'uri': uri, 'mimeType': mime};

class FakeIncomingMediaSource implements IncomingMediaSource {
  final updates = StreamController<void>.broadcast(sync: true);
  final batches = <Future<List<IncomingMedia>>>[];
  int drains = 0;
  void Function()? onTake;
  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<List<IncomingMedia>> takePending() {
    drains++;
    final next = batches.isEmpty
        ? Future.value(<IncomingMedia>[])
        : batches.removeAt(0);
    final callback = onTake;
    onTake = null;
    callback?.call();
    return next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'network proposal preserves a direct URL without opening or exposing its query in the title',
    () {
      final incoming = IncomingMedia.fromPlatform(
        proposal('https://video.example/movie.mp4?signature=private'),
      );
      expect(incoming.media?.uri.query, 'signature=private');
      expect(incoming.media?.title, 'movie.mp4');
      expect(incoming.media?.canRemember, isTrue);
      expect(incoming.durableAccess, isFalse);
      expect(incoming.error, isNull);
    },
  );

  test(
    'explicit video MIME supports a direct URL without a filename extension',
    () {
      final incoming = IncomingMedia.fromPlatform(
        proposal('https://video.example/download/42', mime: 'video/mp4'),
      );
      expect(incoming.media, isNotNull);
    },
  );

  test('temporary content grant warns and cannot be remembered', () {
    final incoming = IncomingMedia.fromPlatform({
      ...proposal('content://media/external/video/media/42', mime: 'video/mp4'),
      'readAccess': true,
      'durableAccess': false,
    });
    expect(incoming.media?.title, 'Shared video');
    expect(incoming.media?.canRemember, isFalse);
    expect(incoming.durableAccess, isFalse);
    expect(incoming.warning, contains('temporary'));
  });

  test('confirmed persisted content grant can be remembered', () {
    final incoming = IncomingMedia.fromPlatform({
      ...proposal('content://documents/video/42', mime: 'video/mp4'),
      'readAccess': true,
      'durableAccess': true,
    });
    expect(incoming.media?.canRemember, isTrue);
    expect(incoming.durableAccess, isTrue);
    expect(incoming.warning, isNull);
  });

  test(
    'content requires both declared video type and confirmed read grant',
    () {
      for (final fields in [
        <String, Object?>{'mimeType': 'video/mp4'},
        <String, Object?>{'readAccess': true, 'mimeType': 'image/jpeg'},
        <String, Object?>{'readAccess': true, 'mimeType': 'video/mp4\nprivate'},
      ]) {
        final incoming = IncomingMedia.fromPlatform({
          ...proposal('content://documents/video/42'),
          ...fields,
        });
        expect(incoming.media, isNull);
        expect(incoming.error, isNotNull);
      }
    },
  );

  test(
    'rejects unsupported schemes, paths, credentials, huge and malformed payloads',
    () {
      for (final value in [
        '/storage/emulated/0/movie.mp4',
        'file:///private/movie.mp4',
        'javascript:alert(1)',
        'https://user:secret@video.example/movie.mp4',
        'https://video.example/movie.mp4\nprivate',
        'https://video.example/%zz.mp4',
        'https://video.example/${'a' * 4096}.mp4',
        'https://video.example/watch',
      ]) {
        final incoming = IncomingMedia.fromPlatform(proposal(value));
        expect(
          incoming.media,
          isNull,
          reason: value.length < 100 ? value : 'huge payload',
        );
        expect(incoming.error, isNotNull);
        expect(incoming.error, isNot(contains('secret')));
        expect(incoming.error, isNot(contains(value)));
      }
    },
  );

  test('shared text invitation stays distinct from media', () {
    final incoming = IncomingMedia.fromPlatform({
      'id': 'invite',
      'kind': 'invite',
      'uri': 'meowwatch://join?room=test&server=syncplay.pl&port=8995',
    });
    expect(incoming.invite?.host, 'join');
    expect(incoming.media, isNull);
  });

  test('queue overflow is visible without exposing provider error details', () {
    final incoming = IncomingMedia.fromPlatform({
      ...proposal('https://video.example/movie.mp4'),
      'overflow': true,
    });
    expect(incoming.warning, contains('replaced'));
    final failure = IncomingMedia.fromPlatform({
      'id': 'failure',
      'kind': 'error',
      'errorCode': 'permission_denied',
      'error': 'content://private/file and credentials',
    });
    expect(failure.error, contains('Access'));
    expect(failure.error, isNot(contains('credentials')));
  });

  test(
    'serializes cold and warm drains and deduplicates delivery IDs',
    () async {
      final source = FakeIncomingMediaSource();
      final cold = Completer<List<IncomingMedia>>();
      final first = IncomingMedia.fromPlatform(
        proposal('https://video.example/a.mp4'),
      );
      final second = IncomingMedia.fromPlatform(
        proposal('https://video.example/b.mp4', id: 'two'),
      );
      source.batches.addAll([
        cold.future,
        Future.value([first, second]),
      ]);
      final inbox = IncomingMediaInbox(source);
      final received = <IncomingMedia>[];
      final starting = inbox.start(
        onMedia: received.add,
        onError: (error) => fail('$error'),
      );
      source.updates.add(null);
      source.updates.add(null);
      expect(source.drains, 1);
      cold.complete([first]);
      await starting;
      expect(received.map((item) => item.id), ['one', 'two']);
      expect(source.drains, 2);
      await inbox.dispose();
      await source.updates.close();
    },
  );

  test(
    'synchronous warm event during drain cannot create concurrent intake',
    () async {
      final source = FakeIncomingMediaSource();
      final cold = Completer<List<IncomingMedia>>();
      source.batches.add(cold.future);
      source.onTake = () => source.updates.add(null);
      final inbox = IncomingMediaInbox(source);
      final starting = inbox.start(onMedia: (_) {}, onError: (_) {});
      expect(source.drains, 1);
      cold.complete([]);
      await starting;
      expect(source.drains, 2);
      await inbox.dispose();
      await source.updates.close();
    },
  );

  test(
    'dispose prevents late cold delivery and removes the warm listener',
    () async {
      final source = FakeIncomingMediaSource();
      final pending = Completer<List<IncomingMedia>>();
      source.batches.add(pending.future);
      final inbox = IncomingMediaInbox(source);
      final received = <IncomingMedia>[];
      final starting = inbox.start(onMedia: received.add, onError: (_) {});
      await inbox.dispose();
      pending.complete([
        IncomingMedia.fromPlatform(proposal('https://video.example/a.mp4')),
      ]);
      await starting;
      expect(received, isEmpty);
      expect(source.updates.hasListener, isFalse);
      await source.updates.close();
    },
  );

  test(
    'source errors are redacted and a later incoming share still works',
    () async {
      final source = FakeIncomingMediaSource();
      source.batches.add(
        Future.error(StateError('https://private.example/a.mp4?secret=yes')),
      );
      final inbox = IncomingMediaInbox(source);
      final errors = <Object>[];
      final received = <IncomingMedia>[];
      await inbox.start(onMedia: received.add, onError: errors.add);
      expect(errors.single.toString(), isNot(contains('secret')));
      source.batches.add(
        Future.value([
          IncomingMedia.fromPlatform(proposal('https://video.example/a.mp4')),
        ]),
      );
      source.updates.add(null);
      await pumpEventQueue();
      expect(received, hasLength(1));
      await inbox.dispose();
      await source.updates.close();
    },
  );

  test(
    'platform source consumes only a bounded batch and performs no media operation',
    () async {
      const methods = MethodChannel('com.meowwatch.mobile/incoming-media');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call.method);
        return List.generate(
          10,
          (index) => proposal('https://video.example/$index.mp4', id: '$index'),
        );
      });
      final received = await AndroidIncomingMediaSource().takePending();
      expect(received, hasLength(8));
      expect(calls, ['drain']);
      messenger.setMockMethodCallHandler(methods, null);
    },
  );
}
