#!/usr/bin/env bash
# Regenerates all app icon sets from source images in assets/icon/:
#   - assets/icon/icon.png      -> main/release icon (Android + macOS)
#   - assets/icon/logo_dev.png  -> debug/dev icon (Android + macOS)
#
# Android and macOS-main go through flutter_launcher_icons, driven by
# flutter_launcher_icons-main.yaml / flutter_launcher_icons-debug.yaml.
#
# macOS's dev icon is handled separately below: flutter_launcher_icons
# always writes macOS icons to a single fixed AppIcon.appiconset
# regardless of flavor, so it can't target the separate AppIcon-Dev
# catalog used for debug/profile builds (see
# macos/Runner/Configs/AppInfo.xcconfig). Requires ImageMagick (`convert`).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Android (main + debug) and macOS (main) via flutter_launcher_icons"
dart run flutter_launcher_icons

if ! command -v convert >/dev/null 2>&1; then
  echo "==> Skipping macOS dev icon: ImageMagick's 'convert' not found (brew install imagemagick)" >&2
  exit 0
fi

echo "==> macOS dev icon from assets/icon/logo_dev.png"
dev_iconset="macos/Runner/Assets.xcassets/AppIcon-Dev.appiconset"
mkdir -p "$dev_iconset"
for size in 16 32 64 128 256 512 1024; do
  convert assets/icon/logo_dev.png -resize "${size}x${size}" "$dev_iconset/app_icon_${size}.png"
done
# Same image-to-size mapping macOS expects for every idiom/scale combination
# an AppIcon.appiconset declares (see AppIcon.appiconset/Contents.json).
cat > "$dev_iconset/Contents.json" <<'EOF'
{
    "info": {
        "version": 1,
        "author": "xcode"
    },
    "images": [
        {"size": "16x16", "idiom": "mac", "filename": "app_icon_16.png", "scale": "1x"},
        {"size": "16x16", "idiom": "mac", "filename": "app_icon_32.png", "scale": "2x"},
        {"size": "32x32", "idiom": "mac", "filename": "app_icon_32.png", "scale": "1x"},
        {"size": "32x32", "idiom": "mac", "filename": "app_icon_64.png", "scale": "2x"},
        {"size": "128x128", "idiom": "mac", "filename": "app_icon_128.png", "scale": "1x"},
        {"size": "128x128", "idiom": "mac", "filename": "app_icon_256.png", "scale": "2x"},
        {"size": "256x256", "idiom": "mac", "filename": "app_icon_256.png", "scale": "1x"},
        {"size": "256x256", "idiom": "mac", "filename": "app_icon_512.png", "scale": "2x"},
        {"size": "512x512", "idiom": "mac", "filename": "app_icon_512.png", "scale": "1x"},
        {"size": "512x512", "idiom": "mac", "filename": "app_icon_1024.png", "scale": "2x"}
    ]
}
EOF

echo "==> Done"
