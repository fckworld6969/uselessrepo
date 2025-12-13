#!/usr/bin/env bash
# aria2c_civitai.sh — aria2c helper to download a civitai model by ID
# Usage: aria2c_civitai.sh [--type lora|checkpoint|auto] [--dest /path/to/dir] <model_id> <output_name>
# Examples:
#  export CIVITAI_TOKEN="..."
#  aria2c_civitai.sh --type checkpoint 2342652 RealisticVisionV2.0.safetensors
#  aria2c_civitai.sh --type lora 1820829 wan2.2_lora.safetensors /workspace/runpod-slim/ComfyUI/models/loras

set -euo pipefail

TYPE="auto"
DEST_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)
      TYPE="$2"; shift 2;;
    --dest)
      DEST_DIR="$2"; shift 2;;
    --help|-h)
      sed -n '1,120p' "$0"; exit 0;;
    --*) echo "Unknown option: $1"; exit 2;;
    *) break;;
  esac
done

MODEL_ID="${1:-}"
OUTNAME="${2:-}"

if [ -z "$MODEL_ID" ] || [ -z "$OUTNAME" ]; then
  echo "Usage: $0 [--type lora|checkpoint|auto] [--dest /path] <model_id> <output_name>"
  exit 1
fi

if [ -z "${CIVITAI_TOKEN:-}" ]; then
  echo "CIVITAI_TOKEN is not set. Export your token and re-run."
  exit 2
fi

# Decide default destination based on type
if [ -z "$DEST_DIR" ]; then
  case "$TYPE" in
    lora) DEST_DIR="/workspace/runpod-slim/ComfyUI/models/loras";;
    checkpoint) DEST_DIR="/workspace/runpod-slim/ComfyUI/models/checkpoints";;
    auto) DEST_DIR="/workspace/runpod-slim/ComfyUI/models/checkpoints";;
    *) DEST_DIR="/workspace/runpod-slim/ComfyUI/models/checkpoints";;
  esac
fi

mkdir -p "$DEST_DIR"
DIRECT_URL="https://civitai.com/api/download/models/${MODEL_ID}?token=${CIVITAI_TOKEN}"

echo "Downloading model $MODEL_ID as $OUTNAME to $DEST_DIR (type=$TYPE)"
if command -v aria2c &>/dev/null; then
  aria2c -c -d "$DEST_DIR" --content-disposition -x 16 -s 16 -o "$OUTNAME" "$DIRECT_URL"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "aria2c failed with exit code $rc"
    exit $rc
  fi
else
  echo "aria2c not found; falling back to curl"
  curl -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" -o "$DEST_DIR/$OUTNAME" "$DIRECT_URL" || exit 3
fi

echo "Download complete: $DEST_DIR/$OUTNAME"
exit 0

