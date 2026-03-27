#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$ROOT_DIR/dist/v2rayE-macos-$VERSION"
ZIP_PATH="$ROOT_DIR/dist/v2rayE-macos-$VERSION.zip"
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

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p "$RELEASE_DIR/assets/core"

cp "$BUILD_DIR/arm64-apple-macosx/release/v2rayE" "$RELEASE_DIR/v2rayE"
cp "$CORE_SOURCE" "$RELEASE_DIR/assets/core/v2ray"
cp "$PAC_SOURCE" "$RELEASE_DIR/assets/proxy.js"

chmod +x "$RELEASE_DIR/v2rayE" "$RELEASE_DIR/assets/core/v2ray"

ditto -c -k --sequesterRsrc --keepParent "$RELEASE_DIR" "$ZIP_PATH"

echo "Release package created: $ZIP_PATH"
