# Momentum

Momentum is a macOS voice-capture app for turning short spoken thoughts into
local Markdown notes. The native Swift implementation records from the
microphone, transcribes audio with a local Parakeet model, and writes the
result next to the recording.

## Current Implementation

The active implementation is the native macOS app in [`native/`](native/).

- Native Swift menu bar application
- Global shortcut: `Command + Shift + Space`
- Local microphone recording
- Optional system-audio recording through ScreenCaptureKit
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

- macOS 14 or newer
- Swift 6
- Microphone and Screen Recording permissions
- Internet access for the initial model download

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
macOS ScreenCaptureKit to capture all system audio and requires Screen
Recording permission; both permissions are requested when Momentum launches,
not when a recording starts.

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
