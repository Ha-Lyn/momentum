"""Small text helpers shared by the bot."""

TELEGRAM_MAX_MESSAGE_LENGTH = 4096


def split_long_text(text: str, limit: int = TELEGRAM_MAX_MESSAGE_LENGTH) -> list[str]:
    """Split ``text`` into chunks no longer than ``limit`` characters.

    Prefers splitting on newline boundaries so chunks stay readable. Telegram
    caps a single message at 4096 characters, so longer transcripts must be
    sent as multiple messages.
    """
    if len(text) <= limit:
        return [text]

    chunks: list[str] = []
    remaining = text
    while remaining:
        if len(remaining) <= limit:
            chunks.append(remaining)
            break

        cut = remaining.rfind("\n", 0, limit)
        if cut <= 0:
            cut = limit
        chunks.append(remaining[:cut])
        remaining = remaining[cut:].lstrip("\n")

    return chunks
