#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"

DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG="$DIST/TranslateDesk-1.6.0.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$DIST/TranslateDesk.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "TranslateDesk" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built: $DMG"
