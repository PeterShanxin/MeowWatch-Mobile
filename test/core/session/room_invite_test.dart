import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/session/room_invite.dart';

const _config = RoomConfig(
  server: 'syncplay.pl',
  port: 8995,
  room: 'cozy-cat',
  username: 'Host',
);

void main() {
  test('deep link pins the successful endpoint and preserves room', () {
    const config = RoomConfig(
      server: 'syncplay.pl',
      port: 8995,
      room: 'cozy-cat',
      username: 'Host',
    );
    final parsed = parseRoomInvite(
      encodeRoomInvite(config).toString(),
      'Guest',
    );
    expect(parsed.server, 'syncplay.pl');
    expect(parsed.port, 8995);
    expect(parsed.room, 'cozy-cat');
    expect(parsed.username, 'Guest');
    expect(parsed.endpointPolicy, SyncplayEndpointPolicy.pinned);
  });
  test('rejects malformed or truncated invitations', () {
    for (final value in [
      '',
      'meowwatch://join?room=test',
      'meowwatch://pair?room=test',
      'x' * 36,
      'bad\nroom',
    ]) {
      expect(() => parseRoomInvite(value, 'Guest'), throwsFormatException);
    }
  });

  test('a direct video the host is playing rides along in the invite', () {
    final media = MediaItem.fromUrl('https://cdn.example/movie.mp4');
    final invite = encodeRoomInvite(_config, media: media);
    expect(invite.queryParameters['video'], 'https://cdn.example/movie.mp4');
    final video = parseInviteVideo(invite.toString());
    expect(video?.uri.toString(), 'https://cdn.example/movie.mp4');
    // The room invite itself must keep working unaffected by the extra param.
    final parsed = parseRoomInvite(invite.toString(), 'Guest');
    expect(parsed.room, 'cozy-cat');
  });

  test('no media loaded leaves the invite unchanged', () {
    final invite = encodeRoomInvite(_config);
    expect(invite.queryParameters.containsKey('video'), isFalse);
    expect(parseInviteVideo(invite.toString()), isNull);
  });

  test('a local file never rides along in the invite', () {
    final local = MediaItem(
      uri: Uri.parse('content://media/external/video/42'),
      title: 'Home video',
    );
    final invite = encodeRoomInvite(_config, media: local);
    expect(invite.queryParameters.containsKey('video'), isFalse);
  });

  test('a link sharedVideoLink rejects never rides along', () {
    final webpage = MediaItem(
      uri: Uri.parse('https://example.com/watch?id=film'),
      title: 'Watch page',
    );
    final invite = encodeRoomInvite(_config, media: webpage);
    expect(invite.queryParameters.containsKey('video'), isFalse);
  });

  test('an invalid video parameter is ignored but the room stays joinable', () {
    final raw =
        'meowwatch://join?room=cozy-cat&server=syncplay.pl&port=8995'
        '&video=not+a+direct+link';
    expect(parseInviteVideo(raw), isNull);
    final parsed = parseRoomInvite(raw, 'Guest');
    expect(parsed.room, 'cozy-cat');
    expect(parsed.server, 'syncplay.pl');
    expect(parsed.port, 8995);
  });

  test('a desktop share code never carries a video', () {
    expect(parseInviteVideo('cozy-cat-movie-night'), isNull);
    expect(parseInviteVideo('cozy-cat-movie-night@syncplay.pl:9000'), isNull);
  });
}
