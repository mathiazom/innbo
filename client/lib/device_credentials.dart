import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A paired device's stored identity: which server it talks to, and the
/// long-lived credential minted once by POST /pairing/exchange (see
/// backend/internal/httpapi/pairing.go).
///
/// Backend API and PowerSync are two separate services (see
/// docker-compose.yml) that may sit behind different reverse-proxy
/// hostnames/paths in a real deployment, so both URLs are collected
/// explicitly at pairing time rather than assumed from one host.
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

  // useDataProtectionKeychain: false — the default Data Protection Keychain
  // requires the app be signed with a real Team ID, which an unsigned
  // .dmg (see docs/INSTALL-MACOS.md) never has, causing every read/write
  // to fail with -34018 regardless of sandboxing or entitlements.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _keyServerUrl = 'server_url';
  static const _keyPowerSyncUrl = 'powersync_url';
  static const _keyDeviceId = 'device_id';
  static const _keyDeviceSecret = 'device_secret';

  static Future<DeviceCredentials?> read() async {
    final values = await _storage.readAll();
    final serverUrl = values[_keyServerUrl];
    final powerSyncUrl = values[_keyPowerSyncUrl];
    final deviceId = values[_keyDeviceId];
    final deviceSecret = values[_keyDeviceSecret];
    if (serverUrl == null ||
        powerSyncUrl == null ||
        deviceId == null ||
        deviceSecret == null) {
      return null;
    }
    return DeviceCredentials(
      serverUrl: serverUrl,
      powerSyncUrl: powerSyncUrl,
      deviceId: deviceId,
      deviceSecret: deviceSecret,
    );
  }

  Future<void> save() async {
    await _storage.write(key: _keyServerUrl, value: serverUrl);
    await _storage.write(key: _keyPowerSyncUrl, value: powerSyncUrl);
    await _storage.write(key: _keyDeviceId, value: deviceId);
    await _storage.write(key: _keyDeviceSecret, value: deviceSecret);
  }

  static Future<void> clear() => _storage.deleteAll();
}
