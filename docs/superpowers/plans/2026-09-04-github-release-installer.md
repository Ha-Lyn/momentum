# GitHub Release Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish signed native Momentum app archives manually to GitHub Releases and install the latest archive into `/Applications` with one curl command.

**Architecture:** Keep native app construction in `native/scripts/build-app.sh`, add a maintainer-only wrapper that stages a versioned app, archives and checksums it, then uses `gh release create` to publish it. Add a standalone POSIX-compatible installer under `scripts/install.sh` that resolves the latest public release, verifies its checksum, safely replaces `/Applications/Momentum.app`, and launches it.

**Tech Stack:** Swift Package Manager, zsh/bash shell scripts, macOS `ditto`, `curl`, `shasum`, `xattr`, GitHub CLI.

## Global Constraints

- The native app supports macOS 15 or newer.
- The bundle identifier remains `com.momentum.native`.
- Publication is manual; no GitHub Actions workflow is added.
- The friend-facing installer requires no Swift, Xcode, Node.js, or GitHub CLI.
- Apple Development signing with a free Apple Developer account is not notarized or Developer ID distribution.
- Privacy permissions are requested by macOS and are never granted by the scripts.
- Existing installations remain untouched until a new archive passes checksum verification.

---

### Task 1: Make the native builder version-aware and installation-ready

**Files:**
- Modify: `native/scripts/build-app.sh`
- Modify: `native/Info.plist`
- Test: shell syntax and a release build

**Interfaces:**
- `build-app.sh` accepts optional environment variable `APP_VERSION`; when set,
  the generated `CFBundleShortVersionString` and `CFBundleVersion` use it.
- `build-app.sh` accepts optional environment variable `CODESIGN_IDENTITY`.
- `build-app.sh` accepts optional environment variable `ALLOW_ADHOC_SIGNING=1`
  only for local builds; publication will not use this override.
- `Info.plist` remains the source default version when `APP_VERSION` is absent.

- [ ] **Step 1: Add version substitution without mutating `Info.plist`**

  In `build-app.sh`, create a temporary plist under the build output, copy
  `Info.plist` into it, and use `/usr/libexec/PlistBuddy` to set both version
  keys when `APP_VERSION` is non-empty. Copy that temporary plist into the
  app bundle. Keep the committed plist at version `1.0`.

- [ ] **Step 2: Make signing behavior explicit**

  Preserve automatic detection of Apple Development and Developer ID
  identities. When no identity exists, allow the existing warning for local
  builds, but fail if `REQUIRE_CODE_SIGNATURE=1` is set. Keep the existing
  entitlements and runtime signing flags.

- [ ] **Step 3: Validate the shell and local app metadata**

  Run:

  ```bash
  zsh -n native/scripts/build-app.sh
  APP_VERSION=1.2.3 REQUIRE_CODE_SIGNATURE=0 native/scripts/build-app.sh
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' native/dist/Momentum.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/dist/Momentum.app/Contents/Info.plist
  ```

  Expected: syntax succeeds, the app builds, the identifier is
  `com.momentum.native`, and the short version is `1.2.3`.

- [ ] **Step 4: Commit**

  ```bash
  git add native/scripts/build-app.sh native/Info.plist
  git commit -m "build: support versioned native app bundles"
  ```

### Task 2: Add the manual GitHub Release publisher

**Files:**
- Create: `native/scripts/publish-release.sh`
- Test: shell syntax and dry-run validation

**Interfaces:**
- Usage: `native/scripts/publish-release.sh VERSION`
- Optional environment: `CODESIGN_IDENTITY`
- Optional environment: `GITHUB_REPOSITORY` defaulting to `Ha-Lyn/momentum`
- Optional environment: `PUBLISH_DRY_RUN=1` builds and stages assets without
  creating a GitHub Release
- Output assets: `Momentum-VERSION.zip` and `Momentum-VERSION.sha256`

- [ ] **Step 1: Implement argument and prerequisite validation**

  Use `set -euo pipefail`. Require exactly one version matching
  `^[0-9]+\.[0-9]+\.[0-9]+([-.+][0-9A-Za-z.-]+)?$`, require `gh`, `swift`,
  `codesign`, `ditto`, and `shasum`, and require `gh auth status` unless
  `PUBLISH_DRY_RUN=1`.

- [ ] **Step 2: Build and verify the versioned app**

  Invoke `build-app.sh` with `APP_VERSION="$VERSION"` and
  `REQUIRE_CODE_SIGNATURE=1`. Verify the app exists, its bundle identifier
  equals `com.momentum.native`, its version equals `VERSION`, and
  `codesign --verify --deep --strict` succeeds.

- [ ] **Step 3: Create deterministic release assets**

  Use a temporary staging directory. Create the ZIP with:

  ```bash
  ditto -c -k --keepParent native/dist/Momentum.app "$staging/Momentum-$VERSION.zip"
  ```

  Generate a checksum containing the archive basename, and retain both files
  in `native/dist/releases/VERSION/`.

- [ ] **Step 4: Publish or print dry-run output**

  In normal mode, run:

  ```bash
  gh release create "v$VERSION" \
    "$zip_path" "$checksum_path" \
    --repo "$GITHUB_REPOSITORY" \
    --title "Momentum $VERSION" \
    --generate-notes
  ```

  In dry-run mode, do not call `gh release create`; print the staged paths and
  the exact release tag that would be created.

- [ ] **Step 5: Validate and commit**

  Run:

  ```bash
  zsh -n native/scripts/publish-release.sh
  PUBLISH_DRY_RUN=1 native/scripts/publish-release.sh 1.2.3
  ```

  Expected: invalid versions fail before building; the valid dry run creates
  both assets, verifies the app signature, and prints the release command.

  ```bash
  git add native/scripts/publish-release.sh
  git commit -m "release: add manual GitHub publisher"
  ```

### Task 3: Add the public one-command installer

**Files:**
- Create: `scripts/install.sh`
- Test: shell syntax and isolated temporary installation tests

**Interfaces:**
- Usage: `curl -fsSL https://raw.githubusercontent.com/Ha-Lyn/momentum/main/scripts/install.sh | bash`
- Optional environment: `GITHUB_REPOSITORY` defaulting to `Ha-Lyn/momentum`
- Optional environment: `INSTALL_DIR` defaulting to `/Applications` for
  testing or alternate installation locations

- [ ] **Step 1: Implement platform and prerequisite checks**

  Use `set -euo pipefail`. Require macOS, verify the major version is at least
  15, and require `curl`, `ditto`, `shasum`, `xattr`, and `open`. Resolve
  `uname -m` and reject architectures other than `arm64` and `x86_64` with a
  clear message.

- [ ] **Step 2: Resolve and download the latest release**

  Use GitHub’s public redirect endpoints:

  ```text
  https://github.com/$GITHUB_REPOSITORY/releases/latest/download/Momentum-LATEST.zip
  ```

  Because the release version is part of the asset name, first fetch the
  latest release metadata from
  `https://api.github.com/repos/$GITHUB_REPOSITORY/releases/latest`, parse the
  simple `tag_name` field with `/usr/bin/sed`, strip the leading `v`, and
  construct the exact ZIP and checksum asset names. Download both into a
  temporary directory. This keeps the installer dependent only on tools
  already listed above.

- [ ] **Step 3: Verify before replacing the installed app**

  Verify the checksum with `shasum -a 256 -c`. Extract into a temporary
  directory with `ditto -x -k`. Verify the extracted app has the expected
  executable, bundle identifier, and version. If
  `/Applications/Momentum.app` is running, fail before changing it.

- [ ] **Step 4: Install and launch**

  Remove the old app only after all validation passes, move the new app into
  `INSTALL_DIR`, remove its quarantine extended attribute with `xattr -dr
  com.apple.quarantine`, and launch it with `open`. Print the required
  Privacy & Security locations and explain that signing is not notarized.

- [ ] **Step 5: Validate and commit**

  Run:

  ```bash
  bash -n scripts/install.sh
  ```

  Use a local fixture server or mocked `curl` responses to verify checksum
  success, checksum failure, unsupported macOS handling, and safe replacement
  behavior without modifying the real `/Applications` directory.

  ```bash
  git add scripts/install.sh
  git commit -m "install: add one-command GitHub release installer"
  ```

### Task 4: Document release and installation workflows

**Files:**
- Modify: `README.md`
- Modify: `native/README.md`

- [ ] **Step 1: Document maintainer release prerequisites**

  Add GitHub CLI installation/authentication, signing identity discovery,
  versioned publish command, dry-run command, and expected release assets.

- [ ] **Step 2: Document friend installation**

  Add the exact curl command, supported macOS version, permissions, first-run
  behavior, free-account warning, upgrade behavior, and uninstall command.

- [ ] **Step 3: Verify documentation references**

  Search for every referenced script and command, then run the documented
  syntax checks and dry-run command. Ensure the root-level installer URL is
  valid for the `main` branch.

- [ ] **Step 4: Commit**

  ```bash
  git add README.md native/README.md
  git commit -m "docs: document manual releases and installation"
  ```

### Task 5: Run the complete verification pass

**Files:**
- Verify: all changed files

- [ ] **Step 1: Run shell syntax checks**

  ```bash
  zsh -n native/scripts/build-app.sh
  zsh -n native/scripts/publish-release.sh
  bash -n scripts/install.sh
  ```

- [ ] **Step 2: Build and inspect a signed release**

  Run the publisher dry run with a test version and verify the generated
  bundle identifier, version, signature, ZIP contents, and checksum.

- [ ] **Step 3: Inspect the final diff**

  ```bash
  git diff main...HEAD --check
  git status --short
  ```

  Expected: no whitespace errors, no generated release artifacts tracked, and
  only the intended scripts, documentation, and spec/plan files changed.

- [ ] **Step 4: Commit any verification-only corrections**

  If verification exposes a script or documentation defect, fix it and run
  the affected checks again before committing with:

  ```bash
  git add <corrected-files>
  git commit -m "fix: address release verification findings"
  ```
