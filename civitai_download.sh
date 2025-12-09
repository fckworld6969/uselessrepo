#!/usr/bin/env bash
# civitai_download.sh — helper to download assets from Civitai API
# Usage: civitai_download.sh <model_id> [asset_name_pattern] [dest_dir]
# Requires: export CIVITAI_TOKEN="your_civitai_token"
# Requires: jq (for JSON parsing). Install on Ubuntu: sudo apt update && sudo apt install -y jq

set -euo pipefail

MODEL_ID="${1:-}"
PATTERN="${2:-}"  # optional substring to match asset filename (case-insensitive)
DEST_DIR="${3:-/runpod-volume/ComfyUI/models/checkpoints}"

if [ -z "$MODEL_ID" ]; then
  echo "Usage: civitai_download.sh <model_id> [asset_name_pattern] [dest_dir]"
  exit 1
fi

if [ -z "${CIVITAI_TOKEN:-}" ]; then
  echo "CIVITAI_TOKEN is not set. Export your token and re-run."
  exit 2
fi

if ! command -v curl &>/dev/null; then
  echo "curl is required but not installed. Install via: sudo apt update && sudo apt install -y curl"
  exit 3
fi

if ! command -v jq &>/dev/null; then
  echo "jq is required to parse Civitai API responses. Install via: sudo apt update && sudo apt install -y jq"
  exit 4
fi

API_URL="https://civitai.com/api/v1/models/${MODEL_ID}/versions"

# Fetch versions and files
resp=$(curl -s -H "Authorization: Bearer ${CIVITAI_TOKEN}" "$API_URL")

# Collect candidate files with name and url
# The API returns a list of versions; each version has a files[] array with {name, url, hash, ...}
candidates=$(echo "$resp" | jq -r '.items[]?.files[]? | {name: .name, url: (.downloadUrl // .url // .fileUrl // .externalUrl // "") } | select(.url!="") | @base64')

if [ -z "$candidates" ]; then
  echo "No downloadable files found in API response for model $MODEL_ID. Response may require different parsing or token scope."
  exit 5
fi

mkdir -p "$DEST_DIR"

# Helper to decode base64 jq output
decode() {
  echo "$1" | base64 --decode
}

# Build list and pick first matching pattern, else pick first with preferred extensions
chosen_url=""
chosen_name=""

if [ -n "$PATTERN" ]; then
  lcpattern=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r line; do
    item=$(decode "$line")
    name=$(echo "$item" | jq -r '.name')
    url=$(echo "$item" | jq -r '.url')
    if [ "$(echo "$name" | tr '[:upper:]' '[:lower:]')" = "" ]; then
      continue
    fi
    if echo "${name,,}" | grep -qi -- "$lcpattern"; then
      chosen_url="$url"
      chosen_name="$name"
      break
    fi
  done <<< "$candidates"
fi

# If none matched pattern, try to find common extensions
if [ -z "$chosen_url" ]; then
  preferred="safetensors|gguf|pt|bin|pth|ckpt"
  while IFS= read -r line; do
    item=$(decode "$line")
    name=$(echo "$item" | jq -r '.name')
    url=$(echo "$item" | jq -r '.url')
    if echo "$name" | grep -E -i "$preferred" >/dev/null 2>&1; then
      chosen_url="$url"
      chosen_name="$name"
      break
    fi
  done <<< "$candidates"
fi

# Fallback: pick first available
if [ -z "$chosen_url" ]; then
  first=$(echo "$candidates" | head -n1)
  if [ -n "$first" ]; then
    chosen_name=$(decode "$first" | jq -r '.name')
    chosen_url=$(decode "$first" | jq -r '.url')
  fi
fi

if [ -z "$chosen_url" ]; then
  echo "Unable to determine a download URL for model $MODEL_ID"
  exit 6
fi

outname="$chosen_name"
outpath="$DEST_DIR/$outname"

if [ -f "$outpath" ]; then
  echo "File already exists: $outpath — skipping"
  exit 0
fi

echo "Downloading '$chosen_name' to $DEST_DIR"

# Prefer using existing download helper if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/download_asset_cpu.sh" ]; then
  "$SCRIPT_DIR/download_asset_cpu.sh" "$chosen_url" "$outname" "$DEST_DIR" || echo "download helper failed, falling back to curl"
  if [ -f "$outpath" ]; then
    echo "Downloaded $outpath"
    exit 0
  fi
fi

# Final curl fallback (include token if present)
curl -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" -o "$outpath" "$chosen_url" || {
  echo "curl failed to download $chosen_url"
  exit 7
}

echo "Downloaded $outpath"
exit 0
