import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/file_match.dart';
import 'package:meowwatch_mobile/core/sync/loaded_file_message.dart';

void main() {
  group('loadedFileMessage', () {
    test('match → in-sync message', () {
      expect(
        loadedFileMessage(fileName: 'movie.mkv', match: FileMatch.match),
        "Loaded matching file — you're in sync!",
      );
    });

    test('mismatch → plain loaded message', () {
      expect(
        loadedFileMessage(fileName: 'movie.mkv', match: FileMatch.mismatch),
        'Loaded movie.mkv',
      );
    });

    test('unknown → plain loaded message', () {
      expect(
        loadedFileMessage(fileName: 'show.mp4', match: FileMatch.unknown),
        'Loaded show.mp4',
      );
    });
  });
}
