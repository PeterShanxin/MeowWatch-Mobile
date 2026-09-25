import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/cast/cast_playback_target.dart';
import 'package:meowwatch_mobile/core/cast/cast_transport.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';

final media = MediaItem.fromUrl('https://media.example.com/movie.mp4');

class ReceiverTransport implements CastTransport {
  final controller = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final calls = <(String, Map<String, Object?>)>[];
  int generation = 1;
  int revision = 0;
  String? token;
  String? owner;
  int disconnections = 0;
  String player = 'paused';
  String session = 'connected';
  int position = 1250;
  int duration = 9000;
  Completer<Map<Object?, Object?>>? command;
  String? failMethod;
  bool loadReady = true;

  Map<Object?, Object?> state() => {
    'generation': generation,
    'owner': owner,
    'revision': ++revision,
    'session': session,
    'receiverName': 'Living room TV',
    'mediaToken': token,
    'player': player,
    'positionMs': position,
    'durationMs': duration,
  };

  void emit() => controller.add(state());

  @override
  Stream<Map<Object?, Object?>> get events => controller.stream;

  @override
  Future<Map<Object?, Object?>> invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((method, arguments));
    if (method == 'connect') {
      owner = arguments['owner'] as String;
      session = 'connected';
      emit();
    } else if (method == 'disconnect') {
      if (arguments['owner'] == owner &&
          arguments['generation'] == generation) {
        if (failMethod == method) {
          throw PlatformException(code: 'cast_command_failed');
        }
        disconnections++;
        owner = null;
        session = 'disconnected';
        emit();
      }
      return state();
    } else if (arguments['owner'] != owner ||
        arguments['generation'] != generation) {
      throw PlatformException(code: 'cast_stale_session');
    }
    if (failMethod == method) {
      throw PlatformException(
        code: 'cast_command_failed',
        message: 'The TV could not complete the playback command.',
      );
    }
    if (method == 'load') {
      token = arguments['mediaToken'] as String;
      if (!loadReady) player = 'loading';
    }
    if (method == 'play' && command != null) return command!.future;
    return state();
  }
}

void main() {
  late ReceiverTransport receiver;
  late CastPlaybackTarget target;

  setUp(() {
    receiver = ReceiverTransport();
    target = CastPlaybackTarget(transport: receiver);
  });
  tearDown(() async {
    await target.close();
    await receiver.controller.close();
  });

  test(
    'public MP4 contract rejects local, credentials, parameters and private addresses',
    () {
      expect(CastPlaybackTarget.supports(media), isTrue);
      for (final url in [
        'file:///movie.mp4',
        'content://video/movie.mp4',
        'http://media.example.com/movie.mp4',
        'https://meow.local/movie.mp4',
        'https://meow.local./movie.mp4',
        'https://localhost/movie.mp4',
        'https://192.168.1.10/movie.mp4',
        'https://127.0.0.1/movie.mp4',
        'https://[::1]/movie.mp4',
        'https://user:password@media.example.com/movie.mp4',
        'https://media.example.com/movie.mp4?token=secret',
        'https://media.example.com/movie.mp4#secret',
        'https://media.example.com/movie.m3u8',
      ]) {
        expect(
          CastPlaybackTarget.supports(
            MediaItem(uri: Uri.parse(url), title: 'Video'),
          ),
          isFalse,
          reason: url,
        );
      }
    },
  );

  test(
    'load awaits a playable receiver status and loads paused at requested position',
    () async {
      await target.connect();
      receiver.loadReady = false;
      var complete = false;
      final loading = target
          .load(media, position: const Duration(seconds: 4))
          .then((_) => complete = true);
      await Future<void>.delayed(Duration.zero);
      expect(complete, isFalse);
      expect(target.snapshot.connection, PlaybackConnection.loading);
      final request = receiver.calls.last.$2;
      expect(request['positionMs'], 4000);
      expect(request['autoplay'], isFalse);
      expect(request['contentType'], 'video/mp4');
      expect(request.containsKey('title'), isFalse);
      receiver.player = 'paused';
      receiver.emit();
      await loading;
      expect(target.snapshot.ready, isTrue);
      expect(target.snapshot.position, const Duration(milliseconds: 1250));
      expect(target.receiverName, 'Living room TV');
    },
  );

  test(
    'buffering, external controls and end map to coherent snapshots',
    () async {
      await target.connect();
      await target.load(media);
      receiver.player = 'buffering';
      receiver.position = 2700;
      receiver.emit();
      expect(target.snapshot.buffering, isTrue);
      expect(target.snapshot.playing, isFalse);
      expect(target.snapshot.position, const Duration(milliseconds: 2700));
      receiver.player = 'playing';
      receiver.emit();
      expect(target.snapshot.playing, isTrue);
      expect(target.snapshot.buffering, isFalse);
      receiver.player = 'ended';
      receiver.emit();
      expect(target.snapshot.ready, isTrue);
      expect(target.snapshot.playing, isFalse);
      expect(target.snapshot.position, const Duration(seconds: 9));
    },
  );

  test('play waits for acknowledgment without optimistic playback', () async {
    await target.connect();
    await target.load(media);
    receiver.command = Completer<Map<Object?, Object?>>();
    var finished = false;
    final playing = target.play().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(target.snapshot.playing, isFalse);
    receiver.player = 'playing';
    receiver.command!.complete(receiver.state());
    await playing;
    expect(target.snapshot.playing, isTrue);
  });

  test(
    'receiver command failure propagates without false playback state',
    () async {
      await target.connect();
      await target.load(media);
      receiver.failMethod = 'play';
      await expectLater(target.play(), throwsA(isA<PlatformException>()));
      expect(target.snapshot.playing, isFalse);
      receiver.failMethod = 'load';
      await expectLater(target.load(media), throwsA(isA<PlatformException>()));
      expect(target.snapshot.connection, PlaybackConnection.failed);
      expect(target.snapshot.error, isNot(contains(media.uri.toString())));
    },
  );

  test(
    'session loss preserves last position and rejects pending old commands',
    () async {
      await target.connect();
      await target.load(media);
      receiver.command = Completer<Map<Object?, Object?>>();
      final pending = target.play();
      final assertion = expectLater(pending, throwsStateError);
      receiver.session = 'suspended';
      receiver.emit();
      expect(target.snapshot.connection, PlaybackConnection.disconnected);
      expect(target.snapshot.position, const Duration(milliseconds: 1250));
      expect(target.snapshot.playing, isFalse);
      receiver.command!.complete(receiver.state());
      await assertion;
    },
  );

  test(
    'late status and replacement session never take over the accepted source',
    () async {
      await target.connect();
      await target.load(media);
      final stale = receiver.state();
      receiver.position = 6000;
      receiver.emit();
      receiver.controller.add(stale);
      expect(target.snapshot.position, const Duration(seconds: 6));
      receiver.generation++;
      receiver.player = 'playing';
      receiver.emit();
      expect(target.snapshot.connection, PlaybackConnection.disconnected);
      expect(target.snapshot.playing, isFalse);
      receiver.generation = 1;
      receiver.emit();
      expect(target.snapshot.connection, PlaybackConnection.disconnected);
      await target.close();
      expect(receiver.calls.last.$2['generation'], 1);
    },
  );

  test(
    'another sender replacing media fails closed rather than syncing wrong video',
    () async {
      await target.connect();
      await target.load(media);
      receiver.token = 'another-sender';
      receiver.player = 'playing';
      receiver.position = 7000;
      receiver.emit();
      expect(target.snapshot.connection, PlaybackConnection.failed);
      expect(target.snapshot.media, media);
      expect(target.snapshot.playing, isFalse);
      expect(target.snapshot.position, Duration.zero);
    },
  );

  test(
    'seek clamps to the accepted receiver duration and close is idempotent',
    () async {
      await target.connect();
      await target.load(media);
      await target.seek(const Duration(seconds: -2));
      expect(receiver.calls.last.$2['positionMs'], 0);
      await target.seek(const Duration(seconds: 20));
      expect(receiver.calls.last.$2['positionMs'], 9000);
      await target.close();
      await target.close();
      expect(
        receiver.calls.where((call) => call.$1 == 'disconnect'),
        hasLength(1),
      );
      await expectLater(target.play(), throwsStateError);
    },
  );

  test(
    'disconnect failure stays visible while local resources close',
    () async {
      await target.connect();
      receiver.failMethod = 'disconnect';
      await expectLater(target.close(), throwsA(isA<PlatformException>()));
      await target.close();
      expect(
        receiver.calls.where((call) => call.$1 == 'disconnect'),
        hasLength(1),
      );
    },
  );

  test(
    'connection and cancellation share an owner before any session event',
    () async {
      await target.connect();
      final owner = receiver.calls.first.$2['owner'];
      expect(owner, isA<String>());
      await target.close();
      expect(receiver.calls.last.$2['owner'], owner);
    },
  );

  test(
    'closing an unconnected observer never disconnects an existing TV',
    () async {
      await target.connect();
      await target.load(media);
      final observer = CastPlaybackTarget(transport: receiver);
      receiver.emit();
      expect(observer.connected, isFalse);
      await expectLater(observer.play(), throwsStateError);
      final before = receiver.calls.length;
      await observer.close();
      expect(receiver.calls.length, before);
      expect(receiver.disconnections, 0);
      expect(target.connected, isTrue);
      await target.close();
      expect(receiver.disconnections, 1);
    },
  );

  test(
    'new owner on the same native session retires old controls and close',
    () async {
      await target.connect();
      await target.load(media);
      final oldOwner = receiver.owner;
      final oldGeneration = receiver.generation;
      receiver.command = Completer<Map<Object?, Object?>>();
      final inFlight = target.play();
      final rejected = expectLater(inFlight, throwsStateError);
      final replacement = CastPlaybackTarget(transport: receiver);
      await replacement.connect();
      expect(receiver.generation, oldGeneration);
      expect(receiver.owner, isNot(oldOwner));
      expect(target.connected, isFalse);
      expect(target.snapshot.connection, PlaybackConnection.disconnected);
      receiver.command!.complete(receiver.state());
      await rejected;
      await expectLater(target.pause(), throwsStateError);
      await target.close();
      expect(receiver.disconnections, 0);
      expect(replacement.connected, isTrue);
      await replacement.load(media);
      await replacement.close();
      expect(receiver.disconnections, 1);
    },
  );
}
