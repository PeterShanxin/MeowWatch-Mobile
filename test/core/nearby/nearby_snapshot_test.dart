import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_snapshot.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

Map<String, Object?> nearbySnapshotFixture({
  String? desktopId,
  String? epoch,
}) => {
  'desktop': <String, Object?>{
    'id': desktopId ?? encodeBytes(List.filled(16, 1)),
    'name': 'Living room',
  },
  'session': {
    'epoch': epoch ?? encodeBytes(List.filled(16, 2)),
    'mode': 'synced',
    'username': 'Cat',
    'connection': 'connected',
    'room': 'Movie night',
    'server': 'sync.example.test',
    'port': 8997,
  },
  'playback': <String, Object?>{
    'status': 'ready',
    'playing': false,
    'buffering': false,
    'positionMs': 1000,
    'durationMs': 90000,
    'media': {'id': 'opaque-media-id', 'title': 'Movie.mp4'},
  },
  'participants': [
    {'username': 'Cat', 'isSelf': true},
    {'username': 'Friend', 'isSelf': false},
  ],
  'chat': [
    {
      'username': 'Friend',
      'text': 'Hello',
      'receivedAtUnixMs': 1700000000000,
      'system': false,
      'isMine': false,
    },
  ],
};

void main() {
  test('maps desktop state without exposing or loading a phone file', () {
    final raw = nearbySnapshotFixture();
    final playback = raw['playback']! as Map<String, Object?>;
    (playback['media']! as Map<String, Object?>)['shareableUrl'] =
        'https://example.test/movie.mp4';
    final state = NearbySnapshot.parse(raw);
    expect(state.desktopName, 'Living room');
    expect(state.room?.room, 'Movie night');
    expect(state.room?.password, isNull);
    expect(state.playback.connection, PlaybackConnection.ready);
    expect(state.playback.media!.uri.scheme, 'meowwatch-desktop');
    expect(state.playback.media!.isNetwork, isFalse);
    expect(state.playback.position, const Duration(seconds: 1));
    expect(state.participants, {'Friend'});
    expect(state.messages.single.text, 'Hello');
    expect(() => state.participants.add('Another'), throwsUnsupportedError);
    expect(() => state.messages.clear(), throwsUnsupportedError);
  });

  test('local desktop and unknown media duration remain usable', () {
    final raw = nearbySnapshotFixture();
    raw['session'] = {
      'epoch': encodeBytes(List.filled(16, 2)),
      'mode': 'local',
      'connection': 'disconnected',
    };
    final playback = raw['playback']! as Map<String, Object?>;
    playback.remove('durationMs');
    playback.remove('buffering');
    final state = NearbySnapshot.parse(raw);
    expect(state.room, isNull);
    expect(state.username, 'Living room');
    expect(state.playback.duration, Duration.zero);
    expect(state.playback.buffering, isFalse);
  });

  test('remote error content never reaches displayed diagnostics', () {
    final raw = nearbySnapshotFixture();
    final playback = raw['playback']! as Map<String, Object?>;
    playback['error'] = 'secret local path from desktop';
    playback['status'] = 'failed';
    playback['playing'] = true;
    final state = NearbySnapshot.parse(raw);
    expect(state.playback.error, isNot(contains('secret')));
    expect(state.playback.playing, isFalse);
  });

  final invalidChanges = <String, void Function(Map<String, Object?>)>{
    'nonboolean optional buffering': (raw) =>
        (raw['playback']! as Map)['buffering'] = 'true',
    'invalid self participant name': (raw) =>
        ((raw['participants']! as List).first as Map)['username'] = 7,
    'nonstring optional playback error': (raw) =>
        (raw['playback']! as Map)['error'] = {'password': 'secret'},
    'unsupported advertised protocol': (raw) =>
        (raw['desktop']! as Map)['protocolVersion'] = 2,
    'malformed advertised capabilities': (raw) =>
        (raw['desktop']! as Map)['capabilities'] = [7],
    'negative playback revision': (raw) =>
        (raw['playback']! as Map)['revision'] = -1,
    'noninteger sample timestamp': (raw) =>
        (raw['playback']! as Map)['sampledAtUnixMs'] = 1.2,
    'nonboolean optional participant readiness': (raw) =>
        ((raw['participants']! as List).first as Map)['ready'] = 1,
    'nonstring optional chat id': (raw) =>
        ((raw['chat']! as List).first as Map)['id'] = 7,
    'malformed identity': (raw) => (raw['desktop']! as Map)['id'] = 'bad',
    'out of range position': (raw) =>
        (raw['playback']! as Map)['positionMs'] = -1,
    'oversized participants': (raw) => raw['participants'] = List.filled(257, {
      'username': 'Peer',
      'isSelf': false,
    }),
    'oversized chat': (raw) =>
        raw['chat'] = List.filled(101, (raw['chat']! as List).first),
    'invalid chat timestamp': (raw) =>
        ((raw['chat']! as List).first as Map)['receivedAtUnixMs'] =
            8640000000000001,
    'invalid connection status': (raw) =>
        (raw['session']! as Map)['connection'] = 'maybe',
  };
  for (final entry in invalidChanges.entries) {
    test('rejects ${entry.key}', () {
      final raw = nearbySnapshotFixture();
      entry.value(raw);
      expect(() => NearbySnapshot.parse(raw), throwsA(isA<NearbyException>()));
    });
  }
}
