# Momentum Native

Native macOS port of the Electron prototype that lives in [`app/`](../app/).

## What is ported

- Menu bar app with no dock presence
- Global shortcut: `Command + Shift + Space`
- Floating recording indicator
- Local microphone recording
- Whisper transcription via OpenAI API
- Markdown file output in `~/Documents/Momentum Eigenvalues`

## What is intentionally not ported

These items appear in the PRD but are not implemented in the Electron codebase, so they were not carried into the Swift port:

- GPT analysis step
- Offline queue / retry processing
- Config persistence
- Passive window / browser context capture
- Indexing / note connections

## Requirements

- macOS 13+
- Swift 6
- An OpenAI API key available in one of these places:
  - `OPENAI_API_KEY`
  - `OPEN_API_KEY`
  - `~/Library/Application Support/Momentum/config.json`

Example config file:

```json
{
  "openAIAPIKey": "sk-..."
}
```

The config file fallback exists because Finder-launched macOS apps do not reliably inherit shell environment variables.

## Run in development

```bash
cd native
swift run
```

## Build a `.app` bundle

```bash
cd native
./scripts/build-app.sh
open dist/Momentum.app
```

The bundle script exists because the current machine only has Command Line Tools available, not full Xcode.
