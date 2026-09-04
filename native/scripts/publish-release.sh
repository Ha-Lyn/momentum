#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
PROGRAM_NAME="$0"
BUILD_SCRIPT="$SCRIPT_DIR/build-app.sh"
APP_PATH="$ROOT_DIR/native/dist/Momentum.app"
RELEASES_DIR="$ROOT_DIR/native/dist/releases"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Ha-Lyn/momentum}"
PUBLISH_DRY_RUN="${PUBLISH_DRY_RUN:-0}"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+([-.+][0-9A-Za-z.-]+)?$'

usage() {
  echo "Usage: $PROGRAM_NAME VERSION" >&2
}

if (( $# != 1 )); then
  usage
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ $VERSION_PATTERN ]]; then
  echo "Error: invalid version '$VERSION'" >&2
  usage
  exit 1
fi

for tool in gh swift codesign ditto lipo shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required command not found: $tool" >&2
    exit 1
  fi
done

if [[ "$PUBLISH_DRY_RUN" != "1" ]]; then
  gh auth status
fi

if [[ "${CODESIGN_IDENTITY:-}" == "-" ]]; then
  echo "Error: an ad-hoc codesigning identity cannot be used for a release" >&2
  exit 1
fi

APP_VERSION="$VERSION" REQUIRE_CODE_SIGNATURE=1 "$BUILD_SCRIPT"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: expected app bundle was not built: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST")
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ "$BUNDLE_IDENTIFIER" != "com.momentum.native" ]]; then
  echo "Error: unexpected bundle identifier: $BUNDLE_IDENTIFIER" >&2
  exit 1
fi

if [[ "$SHORT_VERSION" != "$VERSION" || "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "Error: app version does not match $VERSION (short=$SHORT_VERSION, bundle=$BUNDLE_VERSION)" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Error: expected app executable was not built: $EXECUTABLE_PATH" >&2
  exit 1
fi

if ! EXECUTABLE_ARCHITECTURES=$(lipo -archs "$EXECUTABLE_PATH" 2>/dev/null); then
  echo "Error: could not inspect release executable architecture: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ "$EXECUTABLE_ARCHITECTURES" != "arm64" ]]; then
  echo "Error: release executable must be arm64-only (found: $EXECUTABLE_ARCHITECTURES)" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
SIGNATURE_DETAILS=$(codesign -dvv "$APP_PATH" 2>&1)
if [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]]; then
  echo "Error: release app has an ad-hoc signature" >&2
  exit 1
fi

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/momentum-release.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

ZIP_NAME="Momentum-$VERSION.zip"
CHECKSUM_NAME="Momentum-$VERSION.sha256"
STAGED_ZIP="$STAGING_DIR/$ZIP_NAME"
STAGED_CHECKSUM="$STAGING_DIR/$CHECKSUM_NAME"

cd "$ROOT_DIR"
ditto -c -k --keepParent "native/dist/Momentum.app" "$STAGED_ZIP"
(
  cd "$STAGING_DIR"
  shasum -a 256 "$ZIP_NAME" > "$CHECKSUM_NAME"
)

VERSION_RELEASE_DIR="$RELEASES_DIR/$VERSION"
rm -rf "$VERSION_RELEASE_DIR"
mkdir -p "$VERSION_RELEASE_DIR"
ZIP_PATH="$VERSION_RELEASE_DIR/$ZIP_NAME"
CHECKSUM_PATH="$VERSION_RELEASE_DIR/$CHECKSUM_NAME"
cp "$STAGED_ZIP" "$ZIP_PATH"
cp "$STAGED_CHECKSUM" "$CHECKSUM_PATH"

RELEASE_COMMAND=(
  gh release create "v$VERSION"
  "$ZIP_PATH" "$CHECKSUM_PATH"
  --repo "$GITHUB_REPOSITORY"
  --title "Momentum $VERSION"
  --generate-notes
)
if [[ "$VERSION" == *-* ]]; then
  RELEASE_COMMAND+=(--prerelease)
fi

if [[ "$PUBLISH_DRY_RUN" == "1" ]]; then
  echo "Dry run: staged $ZIP_PATH"
  echo "Dry run: staged $CHECKSUM_PATH"
  echo "Dry run: would create tag v$VERSION"
  printf '%q ' "${RELEASE_COMMAND[@]}"
  printf '\n'
  exit 0
fi

"${RELEASE_COMMAND[@]}"
