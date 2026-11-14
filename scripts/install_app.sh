#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="/Applications"
OPEN_AFTER=true
REBUILD=true

usage() {
  cat <<'EOF'
Build and install TranslateDesk.app.

Usage:
  ./install.sh [--user] [--system] [--no-open] [--skip-build]

Options:
  --user       Install into ~/Applications without sudo
  --system     Install into /Applications (default)
  --no-open    Do not launch after installation
  --skip-build Reuse dist/TranslateDesk.app
  -h, --help   Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) TARGET_DIR="$HOME/Applications" ;;
    --system) TARGET_DIR="/Applications" ;;
    --no-open) OPEN_AFTER=false ;;
    --skip-build) REBUILD=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

APP_SRC="$ROOT/dist/TranslateDesk.app"
if [[ "$REBUILD" == true || ! -d "$APP_SRC" ]]; then
  "$ROOT/scripts/build_app.sh"
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "Expected built app at $APP_SRC" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_SRC"

osascript -e 'tell application id "com.greyson.translatedesk" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
  if ! pgrep -x TranslateDesk >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
pkill -x TranslateDesk >/dev/null 2>&1 || true

APP_DEST="$TARGET_DIR/TranslateDesk.app"
if [[ "$TARGET_DIR" == "/Applications" && ! -w "$TARGET_DIR" ]]; then
  echo "Installing into /Applications requires administrator permission."
  sudo rm -rf "$APP_DEST"
  sudo ditto "$APP_SRC" "$APP_DEST"
  sudo xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
else
  mkdir -p "$TARGET_DIR"
  rm -rf "$APP_DEST"
  ditto "$APP_SRC" "$APP_DEST"
  xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
fi

# A successful install has one canonical app bundle. Keep the binary and
# dictionaries only in /Applications (or the selected user Applications folder),
# not a second launchable copy in dist/.
codesign --verify --deep --strict "$APP_DEST"
rm -rf "$APP_SRC"

echo "Installed: $APP_DEST"
echo "Global shortcut: Option + A"
echo "Closing or minimizing the main window keeps TranslateDesk in the menu bar."

if [[ "$OPEN_AFTER" == true ]]; then
  open "$APP_DEST"
fi
