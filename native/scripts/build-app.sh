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

INFO_PLIST_SRC="$ROOT_DIR/Info.plist"
INFO_PLIST_TMP="$BUILD_DIR/Info.plist"
cp "$INFO_PLIST_SRC" "$INFO_PLIST_TMP"
if [[ -n "${APP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST_TMP"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$INFO_PLIST_TMP"
fi
cp "$INFO_PLIST_TMP" "$CONTENTS_DIR/Info.plist"

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

sign_app_bundle() {
  local identity="$1"
  local -a args=(
    --force
    --options runtime
    --entitlements "$ROOT_DIR/MomentumNative.entitlements"
  )
  if [[ "$identity" != "-" ]]; then
    args+=(--timestamp)
  fi
  codesign "${args[@]}" --sign "$identity" "$APP_DIR"
}

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  sign_app_bundle "$CODESIGN_IDENTITY"
  echo "Signed $APP_DIR with $CODESIGN_IDENTITY"
elif [[ "${REQUIRE_CODE_SIGNATURE:-}" == "1" ]]; then
  echo "Error: no codesigning identity found and REQUIRE_CODE_SIGNATURE=1" >&2
  exit 1
elif [[ "${ALLOW_ADHOC_SIGNING:-}" == "1" ]]; then
  sign_app_bundle "-"
  echo "Ad-hoc signed $APP_DIR (ALLOW_ADHOC_SIGNING=1)"
else
  echo "Warning: no codesigning identity found; the app is ad-hoc signed and macOS permissions will reset after every rebuild."
fi

echo "Built $APP_DIR"
