/// Test Store is supported only in debuggable development builds.
String? revenueCatKeyProblem(String key, {required bool debugBuild}) {
  final value = key.trim();
  if (value.isEmpty) return 'missing_public_sdk_key';
  if (value.startsWith('sk_')) return 'server_key_not_allowed';
  if (!debugBuild && value.startsWith('test_')) {
    return 'test_store_requires_debug_build';
  }
  return null;
}
