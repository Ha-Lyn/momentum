# Momentum Native

Native macOS implementation of Momentum. The project-level guide is in
[`../README.md`](../README.md).

## Requirements

- macOS 14+
- Swift 6
- Internet access for the first local model download
- Microphone and Screen Recording permissions

## Run in development

```bash
swift run
```

## Build a `.app` bundle

```bash
./scripts/build-app.sh
open dist/Momentum.app
```

For stable macOS Screen Recording permissions, install an Apple Development
certificate and pass its exact identity when building:

```bash
security find-identity -v -p codesigning
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

The bundle identifier is `com.momentum.native`; keep it unchanged so macOS can
associate permissions with the signed app across rebuilds. Without
`CODESIGN_IDENTITY`, the script builds an ad-hoc app and Screen Recording
permissions may need to be granted again.

The app requests microphone and system-audio access when it launches. Enable
Momentum under Privacy & Security > Screen Recording if macOS does not grant
system-audio access automatically. The Options > Audio Channels menu remembers
the selected channels and defaults to Input only.

The app uses FluidAudio to download and cache the Parakeet TDT v3 model on the
first transcription. Audio inference runs locally after the model is cached.

Input and Output are captured into separate files. Their names begin with
`input-` and `output-`, respectively, and each file receives its own Markdown
transcription.
