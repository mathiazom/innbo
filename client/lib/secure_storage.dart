import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// flutter_secure_storage's macOS keychain service (kSecAttrService) defaults
// to the same hardcoded string for every app — unrelated to
// CFBundleIdentifier. Without overriding it, a locally-run debug build and
// the installed release build (see the .dev bundle id suffix in
// macos/Runner/Configs/AppInfo.xcconfig) would read/write the exact same
// keychain item, silently bleeding stored values between them since this
// app isn't sandboxed.
const _keychainAccountName = kReleaseMode
    ? 'be.biku.innbo'
    : 'be.biku.innbo.dev';

// The default macOS Keychain backend requires the app be signed with a real
// Team ID, which an unsigned .dmg (see docs/INSTALL-MACOS.md) never has,
// causing every read/write to fail with -34018 regardless of sandboxing or
// entitlements — opt into the legacy (non-Team-ID) Keychain backend instead.
//
// Shared by every local secure-storage user in this app (see
// device_credentials.dart, sync/stored_schema_version.dart) so this
// workaround only needs fixing in one place if it ever changes.
const secureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: _keychainAccountName,
  ),
);
