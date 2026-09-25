import 'file_match.dart';

/// System message shown in chat when the local user loads a video file.
///
/// When [match] is [FileMatch.match] the peer has the same file and we're
/// immediately in sync — say so. Any other result falls back to a plain
/// `Loaded <filename>` line so "jumped to 00:00" never appears on first load.
String loadedFileMessage({required String fileName, required FileMatch match}) {
  if (match == FileMatch.match) {
    return "Loaded matching file — you're in sync!";
  }
  return 'Loaded $fileName';
}
