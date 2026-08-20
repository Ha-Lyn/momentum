"""Local speech-to-text via whisper.cpp (whisper-cli binary)."""

import asyncio
import logging
import subprocess
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)


def ffmpeg_to_wav(src: Path, ffmpeg_bin: str, out: Path) -> None:
    """Decode any audio to 16 kHz mono WAV (whisper.cpp's native input)."""
    subprocess.run(
        [
            ffmpeg_bin,
            "-nostdin",
            "-i", str(src),
            "-ar", "16000",
            "-ac", "1",
            "-f", "wav",
            "-y", str(out),
        ],
        check=True,
        capture_output=True,
        text=True,
    )


def build_command(
    binary: str,
    model: str,
    wav: Path,
    out_base: Path,
    language: str,
    threads: int | None = None,
) -> list[str]:
    """Build the whisper-cli invocation. Writes transcript to ``out_base`` + ".txt"."""
    cmd = [
        binary,
        "-m", model,
        "-f", str(wav),
        "-l", language,
        "-nt",
        "-np",
        "-otxt",
        "-of", str(out_base),
    ]
    if threads:
        cmd += ["-t", str(threads)]
    return cmd


class Transcriber:
    """Runs whisper.cpp's ``whisper-cli`` in a worker thread, serialized.

    GPU inference runs best one-at-a-time, so access is guarded by an asyncio
    lock and the blocking subprocess call is pushed off the event loop.
    """

    def __init__(
        self,
        binary: str,
        model: str,
        language: str,
        ffmpeg_bin: str,
        tmp_dir: str,
        threads: int | None = None,
    ) -> None:
        self.binary = binary
        self.model = model
        self.language = language
        self.ffmpeg_bin = ffmpeg_bin
        self.tmp_dir = tmp_dir
        self.threads = threads
        self._lock = asyncio.Lock()

    async def transcribe(self, path: str) -> str:
        async with self._lock:
            return await asyncio.to_thread(self._transcribe_sync, path)

    def _transcribe_sync(self, path: str) -> str:
        src = Path(path)
        logger.info(
            "Transcribing %s (model=%s, language=%s)",
            path, self.model, self.language,
        )

        Path(self.tmp_dir).mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=self.tmp_dir) as td:
            work = Path(td)
            is_wav = src.suffix.lower() == ".wav"
            wav = src if is_wav else work / "audio.wav"
            if not is_wav:
                ffmpeg_to_wav(src, self.ffmpeg_bin, wav)

            out_base = work / "transcript"
            cmd = build_command(
                self.binary, self.model, wav, out_base, self.language, self.threads
            )
            logger.debug("Running: %s", " ".join(cmd))
            try:
                subprocess.run(cmd, check=True, capture_output=True, text=True)
            except subprocess.CalledProcessError as exc:
                logger.error(
                    "whisper-cli failed: %s\nstderr:\n%s",
                    " ".join(cmd), exc.stderr,
                )
                raise

            return out_base.with_suffix(".txt").read_text(encoding="utf-8").strip()
