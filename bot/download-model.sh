#!/usr/bin/env bash
set -euo pipefail

# Downloads a Whisper model in ggml format from the whisper.cpp Hugging Face repo.
#
# Usage: ./download-model.sh [model-name]
#   model-name defaults to "large-v3-turbo". Other options include:
#   large-v3, large-v3-turbo-q5_0, large-v3-turbo-q8_0, medium, small, ...
# The file is saved to ./models/ggml-<model-name>.bin

MODEL="${1:-large-v3-turbo}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${HERE}/models"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL}.bin"

mkdir -p "${DEST_DIR}"

echo "Downloading ggml-${MODEL}.bin"
echo "  from: ${URL}"
echo "  to:   ${DEST_DIR}/ggml-${MODEL}.bin"

curl -L --fail --progress-bar -o "${DEST_DIR}/ggml-${MODEL}.bin" "${URL}"

echo "Done. Model saved to ${DEST_DIR}/ggml-${MODEL}.bin"
