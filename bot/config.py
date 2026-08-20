"""Runtime configuration loaded from environment variables."""

import os
import sys
import tempfile
from dataclasses import dataclass
from typing import Mapping

DEFAULT_BINARY = "whisper-cli"
DEFAULT_MODEL = "models/ggml-large-v3-turbo.bin"
DEFAULT_LANGUAGE = "pt"


@dataclass(frozen=True)
class Config:
    bot_token: str
    whisper_cpp_bin: str
    whisper_cpp_model: str
    whisper_language: str
    whisper_cpp_threads: int | None
    tmp_dir: str
    ffmpeg_bin: str | None


def load_config(environ: Mapping[str, str] | None = None) -> Config:
    """Read configuration from ``environ`` (defaults to ``os.environ``).

    Raises ``SystemExit(1)`` when ``TELEGRAM_BOT_TOKEN`` is missing so the bot
    fails fast with a clear message instead of polling anonymously.
    """
    env = os.environ if environ is None else environ

    token = env.get("TELEGRAM_BOT_TOKEN", "").strip()
    if not token:
        sys.stderr.write(
            "TELEGRAM_BOT_TOKEN is not set. Create a bot with @BotFather and "
            "export TELEGRAM_BOT_TOKEN=<token> before running.\n"
        )
        sys.exit(1)

    # whisper-cli defaults to English, so an explicit language is always passed;
    # empty means "auto-detect".
    language = env.get("WHISPER_LANGUAGE", DEFAULT_LANGUAGE).strip() or "auto"

    threads_raw = env.get("WHISPER_CPP_THREADS", "").strip()
    try:
        threads = int(threads_raw) if threads_raw else None
    except ValueError:
        threads = None

    ffmpeg_bin = env.get("FFMPEG_BIN", "").strip() or None

    return Config(
        bot_token=token,
        whisper_cpp_bin=env.get("WHISPER_CPP_BIN", DEFAULT_BINARY).strip() or DEFAULT_BINARY,
        whisper_cpp_model=env.get("WHISPER_CPP_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL,
        whisper_language=language,
        whisper_cpp_threads=threads,
        tmp_dir=env.get("BOT_TMP_DIR", "").strip()
        or os.path.join(tempfile.gettempdir(), "momentum-bot"),
        ffmpeg_bin=ffmpeg_bin,
    )
