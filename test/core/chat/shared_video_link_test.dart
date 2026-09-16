import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/shared_video_link.dart';

void main() {
  test('standalone direct links retain query without putting it in title', () {
    final media = sharedVideoLink(
      ' https://cdn.example/movie.MP4?token=private ',
    );
    expect(
      media?.uri.toString(),
      'https://cdn.example/movie.MP4?token=private',
    );
    expect(media?.title, 'movie.MP4');
    expect(sharedVideoLink('http://192.168.1.8:8080/video.webm'), isNotNull);
    expect(sharedVideoLink('https://example.com/live.m3u8'), isNotNull);
  });

  test(
    'text, webpages, ambiguous URLs and unsafe syntax stay ordinary chat',
    () {
      for (final message in [
        'hello',
        'Watch https://example.com/a.mp4',
        'https://example.com/a.mp4 https://example.com/b.mp4',
        'https://example.com/a.mp4?next=https://other.example/a.mp4',
        'https://example.com/watch?id=film',
        'https://youtube.com/a.mp4',
        'https://netflix.com/a.mp4',
        'file:///private/a.mp4',
        'javascript:alert(1)',
        'content://video/a.mp4',
        'ftp://example.com/a.mp4',
        'https://user:password@example.com/a.mp4',
        'https://@example.com/a.mp4',
        'https:///a.mp4',
        'https://exa mple.com/a.mp4',
        'https://example.com:65536/a.mp4',
        'https://example.com:0/a.mp4',
        'https://example.com/a%.mp4',
        'https://example.com/a%GG.mp4',
        'https://example.com/a.mp4#fragment',
        'https://example.com/a\n.mp4',
        'https://example.com/a\\b.mp4',
        'https://example.com/a\u202e.mp4',
        'https://exa..mple.com/a.mp4',
        'https://-example.com/a.mp4',
        'https://example.com/a%0a.mp4',
        'https://example.com/a%E2%80%AE.mp4',
        'https://example.com/${'a' * 2048}.mp4',
      ]) {
        expect(sharedVideoLink(message), isNull, reason: message);
      }
    },
  );
}
