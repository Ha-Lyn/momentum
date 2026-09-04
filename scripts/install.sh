#!/bin/bash

set -euo pipefail

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Ha-Lyn/momentum}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_NAME="Momentum.app"
BUNDLE_IDENTIFIER="com.momentum.native"
EXECUTABLE_NAME="MomentumNative"
MINIMUM_MACOS_MAJOR=15
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+([.+-][0-9A-Za-z.-]+)?$'

error() {
  echo "Error: $*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  error "Momentum requires macOS 15 or newer."
fi

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if [[ ! "$MACOS_MAJOR" =~ ^[0-9]+$ ]] || (( MACOS_MAJOR < MINIMUM_MACOS_MAJOR )); then
  error "Momentum requires macOS 15 or newer (this Mac is running macOS $MACOS_VERSION)."
fi

ARCHITECTURE="$(uname -m)"
case "$ARCHITECTURE" in
  arm64|x86_64) ;;
  *) error "Unsupported Mac architecture: $ARCHITECTURE. Momentum supports arm64 and x86_64 Macs." ;;
esac

for tool in curl ditto shasum xattr open; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    error "Required command not found: $tool"
  fi
done

if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  error "Required macOS utility not found: /usr/libexec/PlistBuddy"
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
  error "Installation directory does not exist: $INSTALL_DIR"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/momentum-install.XXXXXX")"
DESTINATION_APP="$INSTALL_DIR/$APP_NAME"
STAGED_APP="$INSTALL_DIR/.Momentum.app.install.$$"
BACKUP_APP="$INSTALL_DIR/.Momentum.app.backup.$$"
REPLACEMENT_STARTED=0
INSTALL_COMPLETE=0
HAD_EXISTING_APP=0

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  set +e

  if ! rm -rf "$TEMP_DIR" "$STAGED_APP"; then
    echo "Warning: some temporary installer files could not be removed." >&2
  fi

  if (( REPLACEMENT_STARTED == 1 && INSTALL_COMPLETE == 0 )); then
    if (( HAD_EXISTING_APP == 1 )); then
      if [[ -e "$BACKUP_APP" || -L "$BACKUP_APP" ]]; then
        if ! rm -rf "$DESTINATION_APP"; then
          echo "Error: could not remove the incomplete installation at $DESTINATION_APP" >&2
        fi
        if [[ -e "$DESTINATION_APP" || -L "$DESTINATION_APP" ]]; then
          echo "Error: the previous Momentum app is preserved at $BACKUP_APP" >&2
        elif ! mv "$BACKUP_APP" "$DESTINATION_APP"; then
          echo "Error: installation failed and the previous Momentum app could not be restored from $BACKUP_APP" >&2
        fi
      elif [[ ! -e "$DESTINATION_APP" && ! -L "$DESTINATION_APP" ]]; then
        echo "Error: installation failed and the previous Momentum app could not be found." >&2
      fi
    elif ! rm -rf "$DESTINATION_APP"; then
      echo "Warning: the incomplete installation could not be removed from $DESTINATION_APP" >&2
    fi
  elif [[ -e "$BACKUP_APP" || -L "$BACKUP_APP" ]]; then
    if ! rm -rf "$BACKUP_APP"; then
      echo "Warning: the previous Momentum backup could not be removed from $BACKUP_APP" >&2
    fi
  fi

  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

is_momentum_running() {
  local executable_path="$DESTINATION_APP/Contents/MacOS/$EXECUTABLE_NAME"
  local process_command
  local process_list

  if ! process_list="$(ps -ax -o command=)"; then
    error "Could not check whether Momentum is running."
  fi

  while IFS= read -r process_command; do
    case "$process_command" in
      *"$executable_path"*) return 0 ;;
    esac
  done <<< "$process_list"

  return 1
}

METADATA_URL="https://api.github.com/repos/$GITHUB_REPOSITORY/releases/latest"
echo "Finding the latest Momentum release..."
RELEASE_METADATA="$(curl -fsSL "$METADATA_URL")" ||
  error "Could not read the latest release from $GITHUB_REPOSITORY."
TAG_NAME="$(printf '%s\n' "$RELEASE_METADATA" |
  /usr/bin/sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
VERSION="${TAG_NAME#v}"

if [[ -z "$TAG_NAME" || ! "$VERSION" =~ $VERSION_PATTERN ]]; then
  error "The latest GitHub release has an invalid or missing tag_name."
fi

ZIP_NAME="Momentum-$VERSION.zip"
CHECKSUM_NAME="Momentum-$VERSION.sha256"
DOWNLOAD_BASE="https://github.com/$GITHUB_REPOSITORY/releases/latest/download"
ZIP_PATH="$TEMP_DIR/$ZIP_NAME"
CHECKSUM_PATH="$TEMP_DIR/$CHECKSUM_NAME"

echo "Downloading Momentum $VERSION..."
curl -fsSL "$DOWNLOAD_BASE/$ZIP_NAME" -o "$ZIP_PATH" ||
  error "Could not download $ZIP_NAME."
curl -fsSL "$DOWNLOAD_BASE/$CHECKSUM_NAME" -o "$CHECKSUM_PATH" ||
  error "Could not download $CHECKSUM_NAME."

IFS= read -r CHECKSUM_LINE < "$CHECKSUM_PATH" || true
if [[ ! "$CHECKSUM_LINE" =~ ^[0-9a-fA-F]{64}[[:space:]][[:space:]\*] ]] ||
  [[ "${CHECKSUM_LINE:66}" != "$ZIP_NAME" ]]; then
  error "The release checksum file has an unexpected format."
fi

echo "Verifying the download..."
(
  cd "$TEMP_DIR"
  shasum -a 256 -c "$CHECKSUM_NAME"
) || error "Checksum verification failed. The existing Momentum installation was not changed."

EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR" ||
  error "Could not extract the Momentum archive."

EXTRACTED_APP="$EXTRACT_DIR/$APP_NAME"
INFO_PLIST="$EXTRACTED_APP/Contents/Info.plist"
EXECUTABLE="$EXTRACTED_APP/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -d "$EXTRACTED_APP" || ! -f "$INFO_PLIST" || ! -x "$EXECUTABLE" ]]; then
  error "The release does not contain a valid Momentum application."
fi

ACTUAL_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null)" ||
  error "Could not read the Momentum bundle identifier."
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null)" ||
  error "Could not read the Momentum version."
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null)" ||
  error "Could not read the Momentum bundle version."

if [[ "$ACTUAL_IDENTIFIER" != "$BUNDLE_IDENTIFIER" ]]; then
  error "Unexpected bundle identifier: $ACTUAL_IDENTIFIER"
fi
if [[ "$SHORT_VERSION" != "$VERSION" || "$BUNDLE_VERSION" != "$VERSION" ]]; then
  error "Release version mismatch (expected $VERSION, found $SHORT_VERSION / $BUNDLE_VERSION)."
fi

if [[ -d "$DESTINATION_APP" ]] && is_momentum_running; then
  error "Momentum is running. Quit Momentum and run the installer again; the existing app was not changed."
fi

rm -rf "$STAGED_APP" "$BACKUP_APP"
mv "$EXTRACTED_APP" "$STAGED_APP" ||
  error "Could not prepare Momentum in $INSTALL_DIR. Check the folder's permissions."

echo "Installing Momentum in $INSTALL_DIR..."
if [[ -e "$DESTINATION_APP" || -L "$DESTINATION_APP" ]]; then
  HAD_EXISTING_APP=1
fi

REPLACEMENT_STARTED=1
if (( HAD_EXISTING_APP == 1 )); then
  mv "$DESTINATION_APP" "$BACKUP_APP" ||
    error "Could not prepare the existing Momentum app for replacement."
fi

mv "$STAGED_APP" "$DESTINATION_APP" ||
  error "Could not replace Momentum. The installer will restore the previous app."
xattr -dr com.apple.quarantine "$DESTINATION_APP" ||
  error "Could not remove the quarantine attribute. The installer will restore the previous app."

INSTALL_COMPLETE=1
if ! rm -rf "$BACKUP_APP"; then
  echo "Warning: Momentum was installed, but its previous backup remains at $BACKUP_APP" >&2
fi

if ! open "$DESTINATION_APP"; then
  echo "Momentum was installed, but macOS could not launch it automatically." >&2
  echo "Open it manually from $INSTALL_DIR." >&2
fi

cat <<EOF

Momentum $VERSION is installed.

If macOS blocks the first launch, open:
  System Settings > Privacy & Security
and use "Open Anyway" for Momentum.

Momentum may also ask for access in:
  System Settings > Privacy & Security > Microphone
  System Settings > Privacy & Security > Screen & System Audio Recording

A free Apple Developer account cannot provide Developer ID distribution or
Apple notarization. Because this build is not notarized, macOS may require the
manual approval above. The installer cannot grant privacy permissions for you.
EOF
