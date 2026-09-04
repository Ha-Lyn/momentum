# Momentum Native

Native macOS implementation of Momentum. The project-level guide is in
[`../README.md`](../README.md).

## Requirements

- macOS 15+
- Swift 6
- Internet access for the first local model download
- Microphone and System Audio Recording permissions

## Run in development

```bash
swift run
```

## Build a `.app` bundle

```bash
./scripts/build-app.sh
open dist/Momentum.app
```

The build script signs the app with the first available codesigning identity
(Developer ID or Apple Development) so macOS permissions survive rebuilds; TCC
identifies ad-hoc builds by binary hash, which changes on every build. To pick
a specific identity:

```bash
security find-identity -v -p codesigning
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

The bundle identifier is `com.momentum.native`; keep it unchanged so macOS can
associate permissions with the signed app across rebuilds.

The app requests microphone and system-audio access when it launches. System
audio is captured with a CoreAudio process tap, which needs the lightweight
"System Audio Recording Only" permission (System Settings > Privacy &
Security > Screen & System Audio Recording) rather than full Screen Recording.
The Options > Audio Channels menu remembers the selected channels and defaults
to Input only.

The app uses FluidAudio to download and cache the Parakeet TDT v3 model on the
first transcription. Audio inference runs locally after the model is cached.

Input and Output are captured into separate files. Their names begin with
`input-` and `output-`, respectively, and each file receives its own Markdown
transcription.

## Publish a release

Publication is manual. The publisher builds a versioned, signed app bundle,
stages release assets locally, and creates a GitHub Release with the GitHub
CLI.

### Prerequisites

Install and authenticate the GitHub CLI:

```bash
brew install gh
gh auth login
gh auth status
```

The publish script also requires `swift`, `codesign`, `ditto`, and `shasum`.
Release builds refuse ad-hoc signatures; you need an Apple Development or
Developer ID Application identity in your login keychain.

List available signing identities:

```bash
security find-identity -v -p codesigning
```

Set `CODESIGN_IDENTITY` to choose one explicitly, or leave it unset and
`build-app.sh` auto-detects the first Developer ID Application or Apple
Development identity in your login keychain. Either identity type works for
publishing; Developer ID is required for distribution outside manual approval,
and notarization is a separate step this script does not run.

A free Apple Developer account provides Apple Development signing only. It
does not include Developer ID Application certificates or Apple notarization.
Friends installing builds signed that way may need to approve the app manually
on first launch (see the project [`README.md`](../README.md)).

Examples:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/publish-release.sh 1.2.3
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/publish-release.sh 1.2.3
```

### Publish

From this directory, pass a semantic version (`MAJOR.MINOR.PATCH`, with an
optional prerelease suffix):

```bash
./scripts/publish-release.sh 1.2.3
```

This builds `dist/Momentum.app` with `APP_VERSION=1.2.3`, verifies the bundle
identifier (`com.momentum.native`), checks the signature, and creates a
GitHub Release tagged `v1.2.3` on `Ha-Lyn/momentum` (override with
`GITHUB_REPOSITORY`).

Expected release assets:

- `Momentum-1.2.3.zip` — signed app archive
- `Momentum-1.2.3.sha256` — SHA-256 checksum for the ZIP

Local copies are retained under `native/dist/releases/1.2.3/`.

### Dry run

Build and stage assets without creating a release:

```bash
PUBLISH_DRY_RUN=1 ./scripts/publish-release.sh 1.2.3
```

Dry run skips `gh auth status` and prints the staged paths plus the `gh release
create` command that would run.

### Share with friends

After publishing, friends can install with:

```bash
curl -fsSL https://raw.githubusercontent.com/Ha-Lyn/momentum/main/scripts/install.sh | bash
```

Published releases are built for arm64 Apple Silicon Macs only.

See the project [`README.md`](../README.md) for first-launch approval, privacy
permissions, upgrade, and uninstall instructions.
