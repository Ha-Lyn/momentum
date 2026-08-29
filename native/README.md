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
