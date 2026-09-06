# Momentum

Momentum is a macOS voice-capture app for turning spoken thoughts into
local Markdown notes. The native Swift implementation records from the
microphone, transcribes audio with a local Parakeet model, and writes the
result next to the recording. It also can record and transcribe system audio 

## Current Implementation

The active implementation is the native macOS app in [`native/`](native/).

- Native Swift menu bar application
- Global shortcut: `Command + Shift + Space`
- Local microphone recording
- Optional system-audio recording through a CoreAudio process tap
- Independently selectable Input and Output audio channels
- Local Parakeet TDT v3 transcription through FluidAudio
- Portuguese, English, and automatic language modes
- Markdown output in `~/Documents/Momentum Eigenvalues`
- No OpenAI API key or cloud transcription service required

The first transcription downloads the model through FluidAudio. Once the model
is cached, audio processing and transcription run locally on the Mac.

The [`app/`](app/) directory contains the earlier Electron prototype. It is
kept for reference and is not the primary implementation.

## Requirements

- macOS 15 or newer
- Microphone and System Audio Recording permissions
- Internet access for the initial model download and for installing from GitHub
  Releases

Developers building from source also need Swift 6.

## Run From Source

```bash
cd native
swift run
```

The app runs as a menu bar application. Grant microphone access when macOS
asks for it, then use `Command + Shift + Space` to start and stop a capture.

## Build The App

The repository includes a bundle script for environments with Swift and the
Command Line Tools, but without the full Xcode application:

```bash
cd native
./scripts/build-app.sh
open dist/Momentum.app
```

The generated application is written to `native/dist/Momentum.app`.

## Install

Install the latest published release into `/Applications` with:

```bash
curl -fsSL https://raw.githubusercontent.com/Ha-Lyn/momentum/main/scripts/install.sh | bash
```

The installer downloads the latest GitHub Release, verifies its SHA-256
checksum, replaces `/Applications/Momentum.app`, removes the download
quarantine attribute, and launches Momentum. It requires macOS 15 or newer on
an arm64 Apple Silicon Mac and uses only standard macOS tools plus `curl`.

To install somewhere else:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Ha-Lyn/momentum/main/scripts/install.sh | \
  INSTALL_DIR="$HOME/Applications" bash
```

### First launch and permissions

On first launch, macOS may block the app when a release is signed with Apple
Development and is not notarized. Publisher builds signed with Developer ID can
still require approval unless they were notarized. If macOS blocks launch, open
**System Settings > Privacy & Security** and choose **Open Anyway** for
Momentum.

Momentum requests access when it launches:

- **System Settings > Privacy & Security > Microphone**
- **System Settings > Privacy & Security > Screen & System Audio Recording**
  (System Audio Recording Only)


### Upgrade

To upgrade, quit Momentum and run the install command again. The installer
verifies the new archive before replacing the existing app and refuses to
change a running installation.


Maintainer release instructions are in [`native/README.md`](native/README.md).

## Output

Each capture is saved under:

```text
~/Documents/Momentum Eigenvalues/
```

The directory contains separate `input-...m4a` and `output-...m4a` recordings
for the enabled channels, each with a matching `.md` transcription. If
transcription fails, Momentum writes a matching `.transcription-error.txt` file
so the recording is not silently lost.

Use the status menu's Options > Audio Channels submenu to select Input, Output,
or both. The selection is remembered and defaults to Input only. Output uses
a CoreAudio process tap to capture system audio and requires System Audio
Recording Only permission (System Settings > Privacy & Security > Screen &
System Audio Recording), not full Screen Recording. Both permissions are
requested when Momentum launches, not when a recording starts.

## Local Model

Momentum uses Parakeet TDT v3 through the Swift package
[FluidAudio](https://github.com/FluidInference/FluidAudio).

Model behavior:

1. The model is downloaded automatically when the first transcription starts.
2. FluidAudio caches the model locally.
3. Later transcriptions load the cached model and do not send audio to a
   remote service.

Model loading can take longer than transcription on the first run. Subsequent
captures reuse the loaded model while the app remains open.

## Repository Layout

```text
native/
  Package.swift                         Swift package definition
  Sources/MomentumNative/               Native macOS application
  scripts/build-app.sh                  .app bundle builder
  scripts/publish-release.sh            Manual GitHub Release publisher

scripts/
  install.sh                            One-command release installer

app/
  src/                                  Electron prototype source
  scripts/                              Prototype transcription helpers

momentum-prd.md                         Original product requirements
```

## Development Notes

Resolve dependencies and build the native target with:

```bash
cd native
swift package resolve
swift build
```

`native/Package.resolved` is committed to keep dependency versions
reproducible. Build output and generated application bundles are ignored by
Git.
