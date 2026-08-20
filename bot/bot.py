"""Momentum Telegram bot: download audio messages and transcribe them locally."""

import logging
import os
import traceback
from pathlib import Path

from dotenv import load_dotenv
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

from config import Config, load_config
from textutil import split_long_text
from transcriber import Transcriber

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("momentum-bot")

# httpx logs the full request URL (including the bot token) at INFO — keep it
# quiet so the token never ends up in log files.
logging.getLogger("httpx").setLevel(logging.WARNING)

HELP_TEXT = (
    "Olá! 👋 Envia-me uma mensagem de voz ou um ficheiro de áudio "
    "e eu transcrevo-o para ti.\n\n"
    "• Suporta mensagens de voz e áudio (.ogg, .m4a, .mp3).\n"
    "• Idioma por omissão: português.\n\n"
    "Envia um áudio para começar!"
)

config: Config
transcriber: Transcriber


def _suffix_for(file) -> str:
    """Best-effort file extension from Telegram's file path, else .ogg."""
    suffix = os.path.splitext(file.file_path or "")[1]
    return suffix or ".ogg"


async def handle_audio(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    if message is None:
        return

    media = message.voice or message.audio or message.video_note
    if media is None:
        await message.reply_text("Envia-me um áudio ou mensagem de voz para eu transcrever.")
        return

    status = await message.reply_text("🎧 A receber o áudio…")
    tmp_path: Path | None = None

    try:
        file = await media.get_file()
        tmp_path = (
            Path(config.tmp_dir)
            / f"{update.update_id}_{file.file_unique_id}{_suffix_for(file)}"
        )
        tmp_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            await file.download_to_drive(tmp_path)
        except Exception:
            logger.warning("Download failed, retrying once (file_id=%s)", media.file_id)
            file = await media.get_file()
            await file.download_to_drive(tmp_path)

        transcript = await transcriber.transcribe(str(tmp_path))

        if not transcript:
            await status.edit_text("Não consegui ouvir nada neste áudio. 🤷")
            return

        chunks = split_long_text(transcript)
        await status.edit_text(chunks[0])
        for extra in chunks[1:]:
            await message.reply_text(extra)

    except Exception:
        logger.error(
            "Failed to process audio (file_id=%s):\n%s",
            media.file_id,
            traceback.format_exc(),
        )
        await status.edit_text("❌ Ocorreu um erro ao transcrever o áudio. Tenta novamente.")

    finally:
        if tmp_path is not None:
            try:
                tmp_path.unlink(missing_ok=True)
            except OSError:
                pass


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_message is None:
        return
    await update.effective_message.reply_text(
        "Envia-me uma mensagem de voz ou um ficheiro de áudio para eu transcrever."
    )


async def handle_other(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_message is None:
        return
    await update.effective_message.reply_text(
        "Isso não é um áudio. Envia-me uma mensagem de voz ou um ficheiro de áudio."
    )


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_message is None:
        return
    await update.effective_message.reply_text(HELP_TEXT)


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_message is None:
        return
    await update.effective_message.reply_text(HELP_TEXT)


def main() -> None:
    global config, transcriber

    load_dotenv(Path(__file__).resolve().parent / ".env")
    config = load_config()

    model = Path(config.whisper_cpp_model)
    if not model.is_absolute():
        model = (Path(__file__).resolve().parent / model).resolve()

    transcriber = Transcriber(
        binary=config.whisper_cpp_bin,
        model=str(model),
        language=config.whisper_language,
        ffmpeg_bin=config.ffmpeg_bin or "ffmpeg",
        tmp_dir=config.tmp_dir,
        threads=config.whisper_cpp_threads,
    )

    application = Application.builder().token(config.bot_token).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_cmd))
    application.add_handler(
        MessageHandler(filters.VOICE | filters.AUDIO | filters.VIDEO_NOTE, handle_audio)
    )
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    application.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, handle_other))

    logger.info(
        "Starting Momentum bot (model=%s, language=%s)",
        config.whisper_cpp_model,
        config.whisper_language,
    )
    application.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
