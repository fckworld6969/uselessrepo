#!/usr/bin/env bash
# download_asset.sh
# Download models/loras/workflows from CivitAI, HuggingFace or plain URLs into volume.
# Usage: download_asset.sh <url> [output_filename] [dest_dir]
# Env: CIVITAI_TOKEN, HF_TOKEN

set -euo pipefail

URL="${1:-}"
OUTNAME="${2:-}"
DEST_DIR="${3:-/runpod-volume/ComfyUI/models/checkpoints}"

if [ -z "$URL" ]; then
  echo "Usage: download_asset.sh <url> [output_filename] [dest_dir]"
  exit 1
fi

mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

echo "Downloading into: $DEST_DIR"

if [[ "$URL" == *"civitai.com"* ]] && [[ "$URL" != *"token="* ]] && [ -n "${CIVITAI_TOKEN:-}" ]; then
  if [[ "$URL" == *"?"* ]]; then
    URL="${URL}&token=${CIVITAI_TOKEN}"
  else
    URL="${URL}?token=${CIVITAI_TOKEN}"
  fi
fi

if [[ "$URL" == *"huggingface.co"* ]] && [ -n "${HF_TOKEN:-}" ]; then
  # Use curl with Authorization header for HF private files
  if [ -n "$OUTNAME" ]; then
    curl -L -H "Authorization: Bearer ${HF_TOKEN}" -o "$OUTNAME" "$URL"
  else
    curl -L -H "Authorization: Bearer ${HF_TOKEN}" -OJ "$URL"
  fi
  echo "Downloaded (HF)"
  exit 0
fi

# Prefer aria2c for speed
if command -v aria2c &>/dev/null; then
  if [ -n "$OUTNAME" ]; then
    aria2c -x 16 -s 16 -o "$OUTNAME" "$URL"
  else
    aria2c -x 16 -s 16 --content-disposition "$URL"
  fi
  echo "Downloaded with aria2c"
  exit 0
fi

# Fallback to curl/wget
if command -v curl &>/dev/null; then
  if [ -n "$OUTNAME" ]; then
    curl -L -o "$OUTNAME" "$URL"
  else
    curl -LO -J "$URL"
  fi
elif command -v wget &>/dev/null; then
  if [ -n "$OUTNAME" ]; then
    wget -O "$OUTNAME" "$URL"
  else
    wget --content-disposition "$URL"
  fi
else
  echo "No downloader available (aria2c, curl, wget). Install one." >&2
  exit 2
fi

echo "Download complete: $(pwd)"
