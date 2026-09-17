import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/billing/sdk_key_policy.dart';

void main() {
  test('release and profile never pass Test Store keys to the native SDK', () {
    expect(
      revenueCatKeyProblem(' test_example ', debugBuild: false),
      'test_store_requires_debug_build',
    );
    expect(revenueCatKeyProblem('test_example', debugBuild: true), isNull);
    expect(revenueCatKeyProblem('goog_example', debugBuild: false), isNull);
  });

  test('missing and secret keys are rejected in every build mode', () {
    for (final debug in [true, false]) {
      expect(
        revenueCatKeyProblem(' ', debugBuild: debug),
        'missing_public_sdk_key',
      );
      expect(
        revenueCatKeyProblem('sk_example', debugBuild: debug),
        'server_key_not_allowed',
      );
    }
  });
}
