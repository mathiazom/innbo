import '../secure_storage.dart';

/// Persists the `kClientVersion` this device last confirmed with an empty
/// PowerSync CRUD queue — see docs/adr/0004-schema-migration-strategy.md.
/// Used by lib/main.dart's `_connect` to detect a leftover queue recorded
/// under an older schema version, after this device has already been
/// updated past a breaking migration.
class StoredSchemaVersion {
  static const _storage = secureStorage;
  static const _key = 'last_confirmed_empty_queue_version';

  static Future<int?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : int.tryParse(raw);
  }

  static Future<void> write(int version) =>
      _storage.write(key: _key, value: '$version');
}
