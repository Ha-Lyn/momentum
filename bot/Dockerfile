# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Momentum Bot — container image
#
# Multi-stage build:
#   stage "test"    — install deps from uv.lock, run the pytest suite
#   stage "runtime" — slim runtime with ffmpeg + whisper.cpp (prebuilt CLI),
#                     deps from uv.lock (no dev group), non-root user
#
# Build/test:
#   podman build --target test ./bot
#   podman build -t momentum-bot ./bot
#   podman compose up --build   (from repo root, see docker-compose.yml)
# ---------------------------------------------------------------------------

# ---- Stage: test ----------------------------------------------------------
FROM python:3.12-slim AS test

ENV PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies (frozen from uv.lock) before copying sources,
# so dependency layers cache well.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --group dev

# Sources + tests
COPY config.py textutil.py transcriber.py bot.py ./
COPY tests ./tests

RUN uv run --frozen pytest -q

# ---- Stage: runtime -------------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    WHISPER_CPP_MODEL=/models/ggml-large-v3-turbo.bin \
    WHISPER_LANGUAGE=pt \
    BOT_TMP_DIR=/tmp/momentum-bot

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /usr/local/bin/uv

# System deps: ffmpeg decodes Telegram audio; curl downloads the model on
# first start; libgomp1 is required by the prebuilt whisper-cli (OpenMP).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
        ca-certificates \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# whisper.cpp prebuilt CLI (CPU) — no compilation needed.
# TARGETARCH is auto-set by podman/docker build (amd64/arm64).
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) WHISPER_ARCH="x64" ;; \
      arm64) WHISPER_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/whisper.tar.gz \
      "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.7/whisper-bin-ubuntu-${WHISPER_ARCH}.tar.gz"; \
    tar -xzf /tmp/whisper.tar.gz -C /tmp; \
    install -m 0755 "/tmp/whisper-bin-ubuntu-${WHISPER_ARCH}/whisper-cli" /usr/local/bin/whisper-cli; \
    rm -rf /tmp/whisper.tar.gz /tmp/whisper-bin-ubuntu-${WHISPER_ARCH}

# App + deps (frozen, without the dev group)
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

COPY config.py textutil.py transcriber.py bot.py ./
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Non-root user; owns the model volume and the staging dir.
RUN useradd --create-home --uid 1000 momentum \
    && mkdir -p /models /tmp/momentum-bot \
    && chown -R momentum:momentum /models /tmp/momentum-bot

USER momentum
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/.venv/bin/python", "/app/bot.py"]
