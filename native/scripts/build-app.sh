#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
APP_NAME="Momentum"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$ROOT_DIR/dist"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/MomentumNative" "$MACOS_DIR/MomentumNative"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/../app/P1.png" "$RESOURCES_DIR/P1.png"

# A stable signing identity is required for macOS TCC permissions (e.g. Screen
# Recording) to survive rebuilds. Ad-hoc signatures are identified by binary
# hash, so every rebuild would invalidate previously granted permissions.
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application|Apple Development/ {print $2; exit}')
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "CODESIGN_IDENTITY not set; auto-detected: $CODESIGN_IDENTITY"
  fi
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/MomentumNative.entitlements" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_DIR"
  echo "Signed $APP_DIR with $CODESIGN_IDENTITY"
else
  echo "Warning: no codesigning identity found; the app is ad-hoc signed and macOS permissions will reset after every rebuild."
fi

echo "Built $APP_DIR"
