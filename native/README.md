# Momentum Native

Native macOS implementation of Momentum. The project-level guide is in
[`../README.md`](../README.md).

## Requirements

- macOS 14+
- Swift 6
- Internet access for the first local model download

## Run in development

```bash
swift run
```

## Build a `.app` bundle

```bash
./scripts/build-app.sh
open dist/Momentum.app
```

The app uses FluidAudio to download and cache the Parakeet TDT v3 model on the
first transcription. Audio inference runs locally after the model is cached.
