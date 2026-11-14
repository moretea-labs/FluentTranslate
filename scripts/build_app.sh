#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product TranslateDesk
BIN_DIR="$(swift build -c release --show-bin-path)"
DIST="$ROOT/dist"
APP="$DIST/TranslateDesk.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/TranslateDesk" "$CONTENTS/MacOS/TranslateDesk"
cp "$ROOT/Sources/TranslateCore/Resources/"*.tdict "$CONTENTS/Resources/"

ICON_SRC="$ROOT/Sources/TranslateDesk/Assets/translatedesk-logo.png"
ICONSET="$DIST/AppIcon.iconset"
ICON_DEST="$CONTENTS/Resources/AppIcon.icns"
if [[ ! -s "$ICON_SRC" ]]; then
  echo "Missing app logo: $ICON_SRC" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$ICON_DEST"
cp "$ICON_SRC" "$CONTENTS/Resources/translatedesk-logo.png"
rm -rf "$ICONSET"

for dictionary in cambridge-en-zh.tdict collins-han-en.tdict collins-cobuild-en.tdict; do
  if [[ ! -s "$CONTENTS/Resources/$dictionary" ]]; then
    echo "Missing bundled dictionary: $dictionary" >&2
    exit 1
  fi
done

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>TranslateDesk</string>
  <key>CFBundleIdentifier</key><string>com.greyson.translatedesk</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>TranslateDesk</string>
  <key>CFBundleDisplayName</key><string>TranslateDesk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.6.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo -n 'APPL????' > "$CONTENTS/PkgInfo"

# The user's installed app reads API keys from macOS Keychain. Ad-hoc signing
# changes its identity on each rebuild and can cause repeated access prompts.
# Require a stable signing identity; never silently fall back to ad-hoc.
SIGNING_IDENTITY="${TRANSLATEDESK_CODESIGN_IDENTITY:-027DE91258B930E819CBCC70A7794CBDD3308E3B}"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
