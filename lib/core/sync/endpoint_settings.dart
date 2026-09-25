/// Small persistence boundary for endpoint discovery. The app can back this
/// with preferences without coupling the protocol to a database or Flutter.
abstract interface class EndpointSettings {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

const kSyncplayEndpointSettingKey = 'syncplay.last_endpoint';

/// Useful for ephemeral sessions and protocol tools.
class MemoryEndpointSettings implements EndpointSettings {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;
}
