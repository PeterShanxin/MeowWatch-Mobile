import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/file_match.dart';
import 'package:meowwatch_mobile/core/sync/loaded_notice.dart';

void main() {
  test('announces "in sync" only when the peer loaded a matching file', () {
    expect(loadedInSyncNotice(match: FileMatch.match), '✓ Loaded — in sync!');
  });

  test('stays silent solo / before the friend loads (unknown match)', () {
    // No peer file yet — a connected friend who hasn't loaded anything is NOT
    // someone we're in sync with (#178).
    expect(loadedInSyncNotice(match: FileMatch.unknown), isNull);
  });

  test('stays silent on a clear mismatch (never a false sync claim)', () {
    expect(loadedInSyncNotice(match: FileMatch.mismatch), isNull);
  });
}
