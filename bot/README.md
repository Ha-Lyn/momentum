# Momentum Bot

A Telegram bot that transcribes voice/audio messages **locally** with
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) — no cloud API, no OpenAI
key, and no heavy Python ML stack. Send it a voice message and it replies with
the transcript, defaulting to Portuguese.

It is a standalone component of the Momentum monorepo (alongside `app/` and
`native/`).

## How it works

```
Telegram (long polling)
  → get_file(file_id)
  → download to temp dir
  → ffmpeg decode → 16 kHz mono WAV
  → whisper-cli -m ggml-large-v3-turbo.bin -l pt  → transcript.txt
  → reply with transcript (split into ≤4096-char messages)
  → temp files deleted
```

## Requirements

- macOS with Apple Silicon (whisper.cpp uses Metal). Tested target: Mac mini M4, 16 GB.
- [`uv`](https://docs.astral.sh/uv/) — `brew install uv` or `pip install uv`.
- `whisper-cpp` — `brew install whisper-cpp` (provides the `whisper-cli` binary).
- `ffmpeg` — `brew install ffmpeg`, or point `FFMPEG_BIN` at an existing binary
  (the repo ships one at `app/bin/ffmpeg`).
- A Telegram bot token from [@BotFather](https://t.me/BotFather).

## Setup

1. Install the tools:

   ```bash
   brew install whisper-cpp ffmpeg
   ```

2. Create a bot with **@BotFather** (`/newbot`) and copy the token.

3. Install Python dependencies:

   ```bash
   cd bot
   uv sync
   ```

4. Download a model (one-time, ~1.6 GB for `large-v3-turbo`):

   ```bash
   ./download-model.sh            # → models/ggml-large-v3-turbo.bin
   # lighter/faster alternative:
   ./download-model.sh large-v3-turbo-q5_0
   ```

5. Configure the token (env var or `bot/.env`):

   ```bash
   export TELEGRAM_BOT_TOKEN=123456:ABC-def...
   # or: cp .env.example .env  and fill in TELEGRAM_BOT_TOKEN
   ```

6. Run it:

   ```bash
   uv run bot.py
   ```

7. Open your bot's chat in Telegram and send a voice message (or an `.ogg` /
   `.m4a` / `.mp3` audio file). The bot replies with the transcript.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | — | **Required.** Bot token from BotFather. |
| `WHISPER_CPP_BIN` | `whisper-cli` | Path to the whisper.cpp CLI binary. |
| `WHISPER_CPP_MODEL` | `models/ggml-large-v3-turbo.bin` | ggml model file; relative paths resolve against `bot/`. |
| `WHISPER_LANGUAGE` | `pt` | Transcription language (ISO-639-1 or `auto`). |
| `WHISPER_CPP_THREADS` | whisper.cpp default (4) | Compute threads (`-t`). |
| `BOT_TMP_DIR` | system temp (`/tmp/momentum-bot`) | Where downloaded audio is staged. |
| `FFMPEG_BIN` | `ffmpeg` from `PATH` | ffmpeg binary used to decode audio to WAV. |

## Model choice

| Model | Size (approx.) | Notes |
|---|---|---|
| `large-v3-turbo` | ~1.6 GB | Best Portuguese quality; faster than real time on M4. Default. |
| `large-v3-turbo-q5_0` | ~0.8 GB | Quantized; near-identical quality, smaller and faster. |
| `large-v3-turbo-q8_0` | ~1.0 GB | Middle ground between fp16 and q5_0. |
| `medium` | ~1.5 GB (fp16) | Solid quality, lighter than large-v3. |

> For most use, `large-v3-turbo-q5_0` is the best speed/size/quality tradeoff;
> the default stays at fp16 `large-v3-turbo` for maximum accuracy.

## Tests

```bash
cd bot
uv run pytest
```

The tests cover configuration parsing, command construction, and message
chunking; they do not require whisper.cpp, ffmpeg, or a bot token.

## Run with Podman / Docker

The bot is fully containerised — `bot/Dockerfile` (multi-stage) plus a
`docker-compose.yml` at the repo root. The image includes ffmpeg and a
prebuilt CPU `whisper-cli` (no Metal, no compilation); the whisper model
(~1.6 GB) is downloaded automatically into a volume on first start.

Prerequisite: Podman with a Linux machine (`podman machine init/start` on
macOS) — or Docker Desktop.

```bash
# 1. Configure the token (required)
cp bot/.env.example bot/.env
#    edit bot/.env  →  TELEGRAM_BOT_TOKEN=123456:ABC-def...

# 2. Build and run
cd <repo-root>
docker compose up --build          # Docker
podman compose up --build          # or Podman (compose provider)
podman-compose up --build          # or podman-compose

# 3. Logs
docker compose logs -f bot
podman logs -f momentum-bot
```

The model is stored in the `momentum-models` volume. To use a different
model, set `WHISPER_CPP_MODEL` in `docker-compose.yml`, e.g.
`/models/ggml-large-v3-turbo-q5_0.bin` — it downloads on next start.

### Build only / run tests in a container

```bash
podman build -t momentum-bot ./bot            # runtime image
podman build --target test ./bot              # runs pytest, no runtime image
```

### Notes

- CPU-only: whisper.cpp runs on the container's CPU (no Metal), so
  transcription is slower than on the host M-series Mac.
- The bot container talks outbound to Telegram only; no ports need mapping.
- Model swaps via volume: remove the volume to force a re-download
  (`podman volume rm momentum-models`).

## Notes & limits

- **Language:** Portuguese is forced by default. Whisper does not distinguish
  pt-PT from pt-BR — set `WHISPER_LANGUAGE=auto` to auto-detect.
- **File size:** Telegram bots can only receive files up to **20 MB**; longer
  recordings will not reach the bot.
- **Concurrency:** transcriptions are serialized (one at a time); simultaneous
  messages are queued and answered in turn.
- **Long transcripts** are split across multiple messages at Telegram's
  4096-character limit.
- **Polling:** uses `getUpdates` long polling — no public URL or webhook needed.
