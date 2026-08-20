import pytest

import config


def test_missing_token_fails(monkeypatch):
    monkeypatch.delenv("TELEGRAM_BOT_TOKEN", raising=False)
    with pytest.raises(SystemExit) as excinfo:
        config.load_config()
    assert excinfo.value.code == 1


def test_defaults(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123:abc")
    for var in (
        "WHISPER_LANGUAGE",
        "WHISPER_CPP_MODEL",
        "WHISPER_CPP_BIN",
        "WHISPER_CPP_THREADS",
        "BOT_TMP_DIR",
        "FFMPEG_BIN",
    ):
        monkeypatch.delenv(var, raising=False)

    cfg = config.load_config()

    assert cfg.bot_token == "123:abc"
    assert cfg.whisper_cpp_bin == "whisper-cli"
    assert cfg.whisper_cpp_model == config.DEFAULT_MODEL
    assert cfg.whisper_language == "pt"
    assert cfg.whisper_cpp_threads is None
    assert cfg.tmp_dir.endswith("momentum-bot")
    assert cfg.ffmpeg_bin is None


def test_empty_language_means_auto(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123:abc")
    monkeypatch.setenv("WHISPER_LANGUAGE", "")

    cfg = config.load_config()

    assert cfg.whisper_language == "auto"


def test_threads_parsed(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123:abc")
    monkeypatch.setenv("WHISPER_CPP_THREADS", "8")

    cfg = config.load_config()

    assert cfg.whisper_cpp_threads == 8


def test_invalid_threads_ignored(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123:abc")
    monkeypatch.setenv("WHISPER_CPP_THREADS", "not-a-number")

    cfg = config.load_config()

    assert cfg.whisper_cpp_threads is None


def test_custom_values(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123:abc")
    monkeypatch.setenv("WHISPER_CPP_BIN", "/opt/bin/whisper-cli")
    monkeypatch.setenv("WHISPER_CPP_MODEL", "/models/ggml-large-v3-turbo-q5_0.bin")
    monkeypatch.setenv("WHISPER_LANGUAGE", "en")
    monkeypatch.setenv("WHISPER_CPP_THREADS", "2")
    monkeypatch.setenv("BOT_TMP_DIR", "/tmp/foo")
    monkeypatch.setenv("FFMPEG_BIN", "/opt/ffmpeg/ffmpeg")

    cfg = config.load_config()

    assert cfg.whisper_cpp_bin == "/opt/bin/whisper-cli"
    assert cfg.whisper_cpp_model == "/models/ggml-large-v3-turbo-q5_0.bin"
    assert cfg.whisper_language == "en"
    assert cfg.whisper_cpp_threads == 2
    assert cfg.tmp_dir == "/tmp/foo"
    assert cfg.ffmpeg_bin == "/opt/ffmpeg/ffmpeg"
