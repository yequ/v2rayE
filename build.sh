#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.0.9}"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="v2rayE.app"
APP_DIR="$DIST_DIR/$APP_NAME"
APP_CONTENTS_DIR="$APP_DIR/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_HELPERS_DIR="$APP_CONTENTS_DIR/Helpers"
APP_FRAMEWORKS_DIR="$APP_CONTENTS_DIR/Frameworks"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
APP_ASSETS_DIR="$APP_RESOURCES_DIR/assets"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
ZIP_PATH="$DIST_DIR/v2rayE-macos-$VERSION.zip"
REPO_OWNER="${REPO_OWNER:-yequ}"
REPO_NAME="${REPO_NAME:-v2rayE}"
APPCAST_URL="${APPCAST_URL:-https://$REPO_OWNER.github.io/$REPO_NAME/appcast.xml}"
RELEASE_TAG="v$VERSION"
RELEASE_NOTES_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$RELEASE_TAG"
RELEASE_DOWNLOAD_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$RELEASE_TAG/$(basename "$ZIP_PATH")"
APPCAST_TEMPLATE_PATH="$DIST_DIR/appcast.xml"
APPCAST_PUBLISH_PATH="${APPCAST_PUBLISH_PATH:-$ROOT_DIR/appcast.xml}"
SPARKLE_FRAMEWORK_SOURCE="$BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_ED_SIGNATURE="${SPARKLE_ED_SIGNATURE:-}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-}"

APP_SUPPORT_DIR="$HOME/Library/Application Support/v2rayE"
PAC_SOURCE_PATH="${PAC_SOURCE_PATH:-$APP_SUPPORT_DIR/proxy.js}"
CORE_SOURCE_PATH="${CORE_SOURCE_PATH:-}"
CORE_SOURCE_CANDIDATES=(
  "$APP_SUPPORT_DIR/core/xray"
  "$APP_SUPPORT_DIR/core/xray/xray"
  "$APP_SUPPORT_DIR/core/v2ray"
  "$APP_SUPPORT_DIR/core/v2ray/v2ray"
  "/opt/homebrew/bin/xray"
  "/usr/local/bin/xray"
  "/opt/homebrew/bin/v2ray"
  "/usr/local/bin/v2ray"
)

resolve_core_source() {
  if [ -n "$CORE_SOURCE_PATH" ] && [ -f "$CORE_SOURCE_PATH" ]; then
    printf '%s\n' "$CORE_SOURCE_PATH"
    return 0
  fi

  local candidate
  for candidate in "${CORE_SOURCE_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

collect_core_sources() {
  local sources=()

  if [ -n "$CORE_SOURCE_PATH" ] && [ -f "$CORE_SOURCE_PATH" ]; then
    sources+=("$CORE_SOURCE_PATH")
  fi

  local candidate candidate_name existing_source existing_name duplicate_found
  for candidate in "${CORE_SOURCE_CANDIDATES[@]}"; do
    if [ ! -f "$candidate" ]; then
      continue
    fi

    candidate_name="$(basename "$candidate")"
    duplicate_found=0
    for existing_source in "${sources[@]}"; do
      existing_name="$(basename "$existing_source")"
      if [ "$existing_name" = "$candidate_name" ]; then
        duplicate_found=1
        break
      fi
    done

    if [ "$duplicate_found" -eq 0 ]; then
      sources+=("$candidate")
    fi
  done

  printf '%s\n' "${sources[@]}"
}

write_default_pac() {
  local target_path="$1"

  cat > "$target_path" <<'PAC'
function FindProxyForURL(url, host) {
    if (isPlainHostName(host) || shExpMatch(host, "*.local")) {
        return "DIRECT";
    }

    return "SOCKS5 127.0.0.1:1080; PROXY 127.0.0.1:1087; DIRECT";
}
PAC
}

sign_bundle() {
  local target="$1"
  /usr/bin/codesign --force --sign - --timestamp=none "$target"
}

ensure_rpath() {
  local binary_path="$1"
  local rpath_value="$2"

  if ! otool -l "$binary_path" | grep -q "$rpath_value"; then
    install_name_tool -add_rpath "$rpath_value" "$binary_path"
  fi
}

find_sparkle_bin_dir() {
  local candidates=()

  if [ -n "$SPARKLE_BIN_DIR" ]; then
    candidates+=("$SPARKLE_BIN_DIR")
  fi

  candidates+=(
    "$ROOT_DIR/.sparkle/bin"
    "$ROOT_DIR/Sparkle/bin"
    "/Applications/Sparkle/bin"
    "/Applications/Sparkle.app/Contents/MacOS/bin"
    "$HOME/Applications/Sparkle/bin"
    "$HOME/Applications/Sparkle.app/Contents/MacOS/bin"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate/generate_keys" ] && [ -x "$candidate/sign_update" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

extract_public_key() {
  local generate_keys_bin="$1/generate_keys"
  local output
  output="$($generate_keys_bin 2>&1)"

  local extracted_key
  extracted_key="$(printf '%s\n' "$output" | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' | head -n 1)"

  if [ -z "$extracted_key" ]; then
    echo "error: 无法从 generate_keys 输出中解析 SUPublicEDKey"
    printf '%s\n' "$output"
    exit 1
  fi

  printf '%s\n' "$extracted_key"
}

resolve_public_key() {
  if [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    printf '%s\n' "$SPARKLE_PUBLIC_ED_KEY"
    return 0
  fi

  local sparkle_bin
  sparkle_bin="$(find_sparkle_bin_dir || true)"
  if [ -z "$sparkle_bin" ]; then
    echo "error: 未提供 SPARKLE_PUBLIC_ED_KEY，且未找到 Sparkle CLI（generate_keys / sign_update）"
    echo "hint: 设置 SPARKLE_BIN_DIR 指向 Sparkle 分发包中的 bin 目录，或直接传入 SPARKLE_PUBLIC_ED_KEY"
    exit 1
  fi

  extract_public_key "$sparkle_bin"
}

resolve_archive_signature() {
  local archive_path="$1"

  if [ -n "$SPARKLE_ED_SIGNATURE" ]; then
    printf '%s\n' "$SPARKLE_ED_SIGNATURE"
    return 0
  fi

  local sparkle_bin
  sparkle_bin="$(find_sparkle_bin_dir || true)"
  if [ -z "$sparkle_bin" ]; then
    echo "error: 未提供 SPARKLE_ED_SIGNATURE，且未找到 Sparkle CLI（generate_keys / sign_update）"
    echo "hint: 设置 SPARKLE_BIN_DIR 指向 Sparkle 分发包中的 bin 目录，或直接传入 SPARKLE_ED_SIGNATURE"
    exit 1
  fi

  local output
  output="$($sparkle_bin/sign_update "$archive_path" 2>&1)"

  local extracted_signature
  extracted_signature="$(printf '%s\n' "$output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"

  if [ -z "$extracted_signature" ]; then
    echo "error: 无法从 sign_update 输出中解析 sparkle:edSignature"
    printf '%s\n' "$output"
    exit 1
  fi

  printf '%s\n' "$extracted_signature"
}

write_appcast() {
  local target_path="$1"
  local archive_length="$2"
  local pub_date="$3"
  local archive_signature="$4"

  mkdir -p "$(dirname "$target_path")"

  cat > "$target_path" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>v2rayE Changelog</title>
        <link>https://github.com/$REPO_OWNER/$REPO_NAME/releases</link>
        <description>v2rayE updates</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$pub_date</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
            <enclosure
                url="$RELEASE_DOWNLOAD_URL"
                sparkle:edSignature="$archive_signature"
                length="$archive_length"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
APPCAST
}

CORE_SOURCE="$(resolve_core_source || true)"
CORE_SOURCES=()
while IFS= read -r core_source; do
  if [ -n "$core_source" ]; then
    CORE_SOURCES+=("$core_source")
  fi
done < <(collect_core_sources)
SPARKLE_PUBLIC_ED_KEY="$(resolve_public_key)"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$ZIP_PATH" "$APPCAST_TEMPLATE_PATH"
mkdir -p "$APP_MACOS_DIR" "$APP_HELPERS_DIR" "$APP_FRAMEWORKS_DIR" "$APP_ASSETS_DIR"

cp "$BUILD_DIR/arm64-apple-macosx/release/v2rayE" "$APP_MACOS_DIR/v2rayE"
BUNDLED_CORE_NAMES=()
for core_source in "${CORE_SOURCES[@]}"; do
  bundled_core_name="$(basename "$core_source")"
  cp "$core_source" "$APP_HELPERS_DIR/$bundled_core_name"
  BUNDLED_CORE_NAMES+=("$bundled_core_name")
done
if [ -f "$PAC_SOURCE_PATH" ]; then
  cp "$PAC_SOURCE_PATH" "$APP_ASSETS_DIR/proxy.js"
else
  write_default_pac "$APP_ASSETS_DIR/proxy.js"
fi
if [ -d "$SPARKLE_FRAMEWORK_SOURCE" ]; then
  cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS_DIR/Sparkle.framework"
fi
if [ -f "$ICON_SOURCE" ]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES_DIR/AppIcon.icns"
fi

chmod +x "$APP_MACOS_DIR/v2rayE"
for bundled_core_name in "${BUNDLED_CORE_NAMES[@]}"; do
  if [ -f "$APP_HELPERS_DIR/$bundled_core_name" ]; then
    chmod +x "$APP_HELPERS_DIR/$bundled_core_name"
  fi
done
ensure_rpath "$APP_MACOS_DIR/v2rayE" "@executable_path/../Frameworks"

cat > "$APP_CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>v2rayE</string>
    <key>CFBundleExecutable</key>
    <string>v2rayE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.v2raye</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>v2rayE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$APPCAST_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAllowsAutomaticUpdates</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

for bundled_core_name in "${BUNDLED_CORE_NAMES[@]}"; do
  if [ -f "$APP_HELPERS_DIR/$bundled_core_name" ]; then
    sign_bundle "$APP_HELPERS_DIR/$bundled_core_name"
  fi
done
if [ -d "$APP_FRAMEWORKS_DIR/Sparkle.framework" ]; then
  /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_FRAMEWORKS_DIR/Sparkle.framework"
fi
sign_bundle "$APP_MACOS_DIR/v2rayE"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

ARCHIVE_LENGTH="$(stat -f%z "$ZIP_PATH")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
SPARKLE_ED_SIGNATURE="$(resolve_archive_signature "$ZIP_PATH")"

write_appcast "$APPCAST_TEMPLATE_PATH" "$ARCHIVE_LENGTH" "$PUB_DATE" "$SPARKLE_ED_SIGNATURE"
write_appcast "$APPCAST_PUBLISH_PATH" "$ARCHIVE_LENGTH" "$PUB_DATE" "$SPARKLE_ED_SIGNATURE"

echo "App bundle created: $APP_DIR"
echo "Release zip created: $ZIP_PATH"
echo "Appcast generated: $APPCAST_TEMPLATE_PATH"
echo "Appcast synced to: $APPCAST_PUBLISH_PATH"
echo "Public ED key: $SPARKLE_PUBLIC_ED_KEY"
echo "Archive signature: $SPARKLE_ED_SIGNATURE"
if [ ${#BUNDLED_CORE_NAMES[@]} -gt 0 ]; then
  echo "Bundled cores: ${BUNDLED_CORE_NAMES[*]}"
  echo "Primary core: ${CORE_SOURCE:-none}"
else
  echo "Bundled core: skipped (app will discover system v2ray at runtime)"
fi
if [ -d "$APP_FRAMEWORKS_DIR/Sparkle.framework" ]; then
  echo "Bundled Sparkle: $APP_FRAMEWORKS_DIR/Sparkle.framework"
else
  echo "Bundled Sparkle: missing"
fi
if [ -f "$PAC_SOURCE_PATH" ]; then
  echo "Bundled PAC: $PAC_SOURCE_PATH"
else
  echo "Bundled PAC: generated default proxy.js"
fi
echo "Next: upload $(basename "$ZIP_PATH") to GitHub Release $RELEASE_TAG"
