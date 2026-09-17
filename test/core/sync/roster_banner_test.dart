import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/sync/roster_banner.dart';

void main() {
  group('rosterPresenceBanner', () {
    test('null when you are first in (no one to announce)', () {
      expect(rosterPresenceBanner([]), isNull);
    });

    test('one friend already here', () {
      expect(rosterPresenceBanner(['Alice']), '🐾 Alice is here');
    });

    test('two friends already here use "are"', () {
      expect(rosterPresenceBanner(['Alice', 'Bob']), '🐾 Alice, Bob are here');
    });
  });
}
