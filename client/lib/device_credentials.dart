import 'package:flutter/foundation.dart' show kReleaseMode;
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

  // flutter_secure_storage's macOS keychain service (kSecAttrService)
  // defaults to the same hardcoded string for every app — unrelated to
  // CFBundleIdentifier. Without overriding it, a locally-run debug build
  // and the installed release build (see the .dev bundle id suffix in
  // macos/Runner/Configs/AppInfo.xcconfig) would read/write the exact same
  // keychain item, silently bleeding paired-device credentials between
  // them since this app isn't sandboxed.
  static const _keychainAccountName = kReleaseMode
      ? 'be.biku.innbo'
      : 'be.biku.innbo.dev';

  // The default macOS Keychain backend requires the app be signed with a
  // real Team ID, which an unsigned .dmg (see docs/INSTALL-MACOS.md)
  // never has, causing every read/write to fail with -34018 regardless
  // of sandboxing or entitlements — opt into the legacy (non-Team-ID)
  // Keychain backend instead.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
      accountName: _keychainAccountName,
    ),
  );
  static const _keyServerUrl = 'server_url';
  static const _keyPowerSyncUrl = 'powersync_url';
  static const _keyDeviceId = 'device_id';
  static const _keyDeviceSecret = 'device_secret';

  // readAll() is avoided: on macOS with usesDataProtectionKeychain: false,
  // the legacy keychain rejects kSecReturnData combined with
  // kSecMatchLimitAll (which readAll always sets), failing every call
  // with -50 regardless of what's stored.
  static Future<DeviceCredentials?> read() async {
    final serverUrl = await _storage.read(key: _keyServerUrl);
    final powerSyncUrl = await _storage.read(key: _keyPowerSyncUrl);
    final deviceId = await _storage.read(key: _keyDeviceId);
    final deviceSecret = await _storage.read(key: _keyDeviceSecret);
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
