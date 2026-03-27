#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="v2rayE.app"
APP_DIR="$DIST_DIR/$APP_NAME"
APP_CONTENTS_DIR="$APP_DIR/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
APP_ASSETS_DIR="$APP_RESOURCES_DIR/assets"
ZIP_PATH="$DIST_DIR/v2rayE-macos-$VERSION.zip"

APP_SUPPORT_DIR="$HOME/Library/Application Support/v2rayE"
PAC_SOURCE="$APP_SUPPORT_DIR/proxy.js"
CORE_SOURCE_CANDIDATES=(
  "$APP_SUPPORT_DIR/core/v2ray"
  "$APP_SUPPORT_DIR/core/v2ray/v2ray"
)

find_core_source() {
  for candidate in "${CORE_SOURCE_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

CORE_SOURCE="$(find_core_source || true)"
if [ -z "$CORE_SOURCE" ]; then
  echo "error: 未找到 v2ray 核心文件，请先放到 $APP_SUPPORT_DIR/core/v2ray 或 $APP_SUPPORT_DIR/core/v2ray/v2ray"
  exit 1
fi

if [ ! -f "$PAC_SOURCE" ]; then
  echo "error: 未找到 PAC 文件：$PAC_SOURCE"
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR" "$APP_ASSETS_DIR/core"

cp "$BUILD_DIR/arm64-apple-macosx/release/v2rayE" "$APP_MACOS_DIR/v2rayE"
cp "$CORE_SOURCE" "$APP_ASSETS_DIR/core/v2ray"
cp "$PAC_SOURCE" "$APP_ASSETS_DIR/proxy.js"

chmod +x "$APP_MACOS_DIR/v2rayE" "$APP_ASSETS_DIR/core/v2ray"

cat > "$APP_CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>v2rayE</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.v2raye</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>v2rayE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>VERSION_PLACEHOLDER</string>
    <key>CFBundleVersion</key>
    <string>BUILD_PLACEHOLDER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

sed -i '' "s/VERSION_PLACEHOLDER/$VERSION/g" "$APP_CONTENTS_DIR/Info.plist"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
sed -i '' "s/BUILD_PLACEHOLDER/$BUILD_NUMBER/g" "$APP_CONTENTS_DIR/Info.plist"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "App bundle created: $APP_DIR"
echo "Release zip created: $ZIP_PATH"
