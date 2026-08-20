from pathlib import Path

from transcriber import build_command


def test_build_command_defaults():
    cmd = build_command(
        "whisper-cli",
        "/models/ggml-large-v3-turbo.bin",
        Path("/tmp/audio.wav"),
        Path("/tmp/transcript"),
        "pt",
    )
    assert cmd == [
        "whisper-cli",
        "-m", "/models/ggml-large-v3-turbo.bin",
        "-f", "/tmp/audio.wav",
        "-l", "pt",
        "-nt",
        "-np",
        "-otxt",
        "-of", "/tmp/transcript",
    ]


def test_build_command_with_threads():
    cmd = build_command(
        "whisper-cli", "m.bin", Path("a.wav"), Path("out"), "auto", threads=8
    )
    assert cmd[-2:] == ["-t", "8"]


def test_build_command_omits_threads_when_none():
    cmd = build_command("whisper-cli", "m.bin", Path("a.wav"), Path("out"), "pt")
    assert "-t" not in cmd
