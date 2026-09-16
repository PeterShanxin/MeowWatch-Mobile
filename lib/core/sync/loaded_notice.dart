import 'file_match.dart';

/// The brief over-video banner shown right after a video opens, or null when
/// there is nothing worth announcing.
///
/// It only claims "in sync" when a friend has loaded the *same* file
/// ([FileMatch.match]) — mirroring the in-chat "Loaded matching file — you're in
/// sync!" line. Solo, or while a connected friend hasn't loaded anything yet
/// ([FileMatch.unknown]), there's nothing to be in sync with; on a clear
/// [FileMatch.mismatch] the dedicated mismatch banner already warns. In all
/// those cases this stays silent and the chat "Loaded …" line carries it (#178).
String? loadedInSyncNotice({required FileMatch match}) {
  if (match != FileMatch.match) return null;
  return '✓ Loaded — in sync!';
}
