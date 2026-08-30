import 'dart:convert';

import 'secure_storage.dart';

/// A paired device's stored identity: which server it talks to, and the
/// long-lived credential minted once by POST /pairing/exchange (see
/// backend/internal/httpapi/pairing.go).
///
/// Backend API and PowerSync are two separate services (see
/// docker-compose.yml) that may sit behind different reverse-proxy
/// hostnames/paths in a real deployment. The backend knows its own
/// PowerSync URL and hands it back in the pairing exchange response, so
/// only the server URL is entered by hand — the PowerSync URL is stored
/// alongside it for convenience but never typed in.
class DeviceCredentials {
  final String serverUrl;
  final String powerSyncUrl;
  final String deviceId;
  final String deviceSecret;

  DeviceCredentials({
    required this.serverUrl,
    required this.powerSyncUrl,
    required this.deviceId,
    required this.deviceSecret,
  });

  static const _storage = secureStorage;
  // All four fields live under one key so macOS Keychain sees a single
  // item instead of four — each item gets its own access-confirmation
  // prompt on first use, so four keys meant four prompts.
  static const _key = 'device_credentials';

  static Future<DeviceCredentials?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DeviceCredentials(
      serverUrl: json['server_url'] as String,
      powerSyncUrl: json['powersync_url'] as String,
      deviceId: json['device_id'] as String,
      deviceSecret: json['device_secret'] as String,
    );
  }

  Future<void> save() async {
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'server_url': serverUrl,
        'powersync_url': powerSyncUrl,
        'device_id': deviceId,
        'device_secret': deviceSecret,
      }),
    );
  }

  static Future<void> clear() => _storage.deleteAll();
}
