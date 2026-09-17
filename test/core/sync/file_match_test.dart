import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/file_match.dart';

void main() {
  group('compareFiles', () {
    test('unknown when peer has not announced a file', () {
      expect(
        compareFiles(localName: 'movie.mkv', localSize: 100),
        FileMatch.unknown,
      );
    });

    test('unknown when local has no file', () {
      expect(
        compareFiles(peerName: 'movie.mkv', peerSize: 100),
        FileMatch.unknown,
      );
    });

    test('size match wins even when names differ', () {
      expect(
        compareFiles(
          localName: 'movie.mkv',
          localSize: 12345,
          peerName: 'renamed.mkv',
          peerSize: 12345,
        ),
        FileMatch.match,
      );
    });

    test('size mismatch wins even when names are identical', () {
      expect(
        compareFiles(
          localName: 'movie.mkv',
          localSize: 12345,
          peerName: 'movie.mkv',
          peerSize: 99999,
        ),
        FileMatch.mismatch,
      );
    });

    test('falls back to normalized name when a size is missing', () {
      expect(
        compareFiles(localName: 'Movie.MKV', peerName: 'movie.mkv'),
        FileMatch.match,
      );
      expect(
        compareFiles(localName: 'a.mkv', peerName: 'b.mkv'),
        FileMatch.mismatch,
      );
    });

    test('name fallback used when only one side reports size', () {
      expect(
        compareFiles(
          localName: 'show.mp4',
          localSize: 500,
          peerName: 'show.mp4',
        ),
        FileMatch.match,
      );
    });

    test('same stream URL matches (size 0 on both sides)', () {
      expect(
        compareFiles(
          localName: 'https://cdn.example.com/a/master.m3u8',
          localSize: 0,
          peerName: 'https://cdn.example.com/a/master.m3u8',
          peerSize: 0,
        ),
        FileMatch.match,
      );
    });

    test('different stream URLs sharing a generic basename do NOT match', () {
      // The whole URL is the identity — comparing only `master.m3u8` would
      // have falsely matched these two different streams.
      expect(
        compareFiles(
          localName: 'https://cdn-a.example.com/master.m3u8',
          localSize: 0,
          peerName: 'https://cdn-b.example.com/master.m3u8',
          peerSize: 0,
        ),
        FileMatch.mismatch,
      );
    });

    test('host is case-insensitive; path and token case are significant', () {
      // Scheme + host differ only in case → same media.
      expect(
        compareFiles(
          localName: 'https://Example.COM/v.mp4',
          peerName: 'https://example.com/v.mp4',
        ),
        FileMatch.match,
      );
      // Path case differs → different media (paths are case-sensitive).
      expect(
        compareFiles(
          localName: 'https://example.com/Video.mp4',
          peerName: 'https://example.com/video.mp4',
        ),
        FileMatch.mismatch,
      );
      // Signed-token case differs → different media.
      expect(
        compareFiles(
          localName: 'https://example.com/v.mp4?token=AbC',
          peerName: 'https://example.com/v.mp4?token=abc',
        ),
        FileMatch.mismatch,
      );
    });

    test('a URL never matches a bare local filename', () {
      expect(
        compareFiles(
          localName: 'https://example.com/movie.mp4',
          peerName: 'movie.mp4',
        ),
        FileMatch.mismatch,
      );
    });
  });
}
