#!/usr/bin/env bash
# download_asset_cpu.sh
# Ubuntu (CPU instance) focused downloader for preparing the persistent volume.
# Usage: download_asset_cpu.sh <url> [output_filename] [dest_dir]
# Example token exports (replace placeholders before running):
#   export CIVITAI_TOKEN="your_civitai_token_here"
#   export HF_TOKEN="your_hf_token_here"

set -euo pipefail

URL="${1:-}"
OUTNAME="${2:-}"
DEST_DIR="${3:-/runpod-volume/ComfyUI/models/checkpoints}"

if [ -z "$URL" ]; then
  echo "Usage: download_asset_cpu.sh <url> [output_filename] [dest_dir]"
  exit 1
fi

mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

echo "(CPU) Downloading into: $DEST_DIR"

# On Ubuntu CPU setup, prefer to ensure aria2c is installed for speed
if ! command -v aria2c &>/dev/null; then
  echo "aria2c not found. Install with: sudo apt update && sudo apt install -y aria2"
fi

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

if command -v aria2c &>/dev/null; then
  if [ -n "$OUTNAME" ]; then
    aria2c -x 16 -s 16 -o "$OUTNAME" "$URL"
  else
    aria2c -x 16 -s 16 --content-disposition "$URL"
  fi
  echo "Downloaded with aria2c"
  exit 0
fi

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
  echo "No downloader available (aria2c, curl, wget). Install aria2c for best performance." >&2
  exit 2
fi

echo "Download finished: $(pwd)"
