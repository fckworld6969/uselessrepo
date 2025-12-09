#!/usr/bin/env bash
# download_asset_gpu.sh
# Downloader optimized for GPU pods (assumes aria2c or curl/wget available).
# Usage: download_asset_gpu.sh <url> [output_filename] [dest_dir]
# Example token exports (replace placeholders before running):
#   export CIVITAI_TOKEN="your_civitai_token_here"
#   export HF_TOKEN="your_hf_token_here"

set -euo pipefail

URL="${1:-}"
OUTNAME="${2:-}"
DEST_DIR="${3:-/runpod-volume/ComfyUI/models/checkpoints}"

if [ -z "$URL" ]; then
  echo "Usage: download_asset_gpu.sh <url> [output_filename] [dest_dir]"
  exit 1
fi

mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

echo "(GPU) Downloading into: $DEST_DIR"

# Append CivitAI token if needed
if [[ "$URL" == *"civitai.com"* ]] && [[ "$URL" != *"token="* ]] && [ -n "${CIVITAI_TOKEN:-}" ]; then
  if [[ "$URL" == *"?"* ]]; then
    URL="${URL}&token=${CIVITAI_TOKEN}"
  else
    URL="${URL}?token=${CIVITAI_TOKEN}"
  fi
fi

if [[ "$URL" == *"huggingface.co"* ]] && [ -n "${HF_TOKEN:-}" ]; then
  if command -v curl &>/dev/null; then
    if [ -n "$OUTNAME" ]; then
      curl -L -H "Authorization: Bearer ${HF_TOKEN}" -o "$OUTNAME" "$URL"
    else
      curl -L -H "Authorization: Bearer ${HF_TOKEN}" -OJ "$URL"
    fi
    echo "Downloaded (HF)"
    exit 0
  fi
fi

# GPU pods usually have aria2c — use it if available
if command -v aria2c &>/dev/null; then
  if [ -n "$OUTNAME" ]; then
    aria2c -x 32 -s 32 -o "$OUTNAME" "$URL"
  else
    aria2c -x 32 -s 32 --content-disposition "$URL"
  fi
  echo "Downloaded with aria2c (high-concurrency)"
  exit 0
fi

# Fallback
if command -v curl &>/dev/null; then
  curl -L -o "${OUTNAME:-}" "$URL" || true
elif command -v wget &>/dev/null; then
  wget -O "${OUTNAME:-}" "$URL" || true
else
  echo "No downloader available (aria2c, curl, wget)." >&2
  exit 2
fi

echo "Download finished: $(pwd)"
