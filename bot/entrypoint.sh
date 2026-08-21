#!/usr/bin/env bash
# Momentum Bot container entrypoint.
#
# Downloads the whisper.cpp model on first start (into the /models volume,
# path from WHISPER_CPP_MODEL) and then execs the container command.
set -euo pipefail

MODEL="${WHISPER_CPP_MODEL:-/models/ggml-large-v3-turbo.bin}"

if [ ! -f "${MODEL}" ]; then
  # Derive the model key from the target filename:
  #   /models/ggml-large-v3-turbo.bin  ->  large-v3-turbo
  MODEL_NAME="$(basename "${MODEL}")"
  MODEL_KEY="${MODEL_NAME#ggml-}"
  MODEL_KEY="${MODEL_KEY%.bin}"
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL_KEY}.bin"

  echo "[entrypoint] Model not found at ${MODEL}; downloading ${URL} ..."
  mkdir -p "$(dirname "${MODEL}")"
  curl -L --fail --progress-bar -o "${MODEL}" "${URL}"
  echo "[entrypoint] Model downloaded."
fi

echo "[entrypoint] Using model: ${MODEL}"
exec "$@"
