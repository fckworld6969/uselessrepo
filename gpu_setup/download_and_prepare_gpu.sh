#!/usr/bin/env bash
# download_and_prepare_gpu.sh
# GPU-focused helper to prepare a ComfyUI volume or container path with
# the models, custom nodes and helper files you specified earlier.
# Usage: download_and_prepare_gpu.sh [--dest <path>] [--skip-custom] [--skip-ipadapter] [--skip-wan] [--skip-civitai]
#
# Notes on Civitai direct downloads:
# - You can prefer using the direct Civitai download API with aria2c by exporting:
#     export CIVITAI_TOKEN="your_civitai_token"
#     export USE_CIVITAI_DIRECT=1
# - The direct aria2c pattern (copy/paste) is:
#     aria2c -c -d "/runpod-volume/ComfyUI/models/checkpoints" --content-disposition -x 16 -s 16 "https://civitai.com/api/download/models/2342652?token=$CIVITAI_TOKEN"
# - When `USE_CIVITAI_DIRECT=1` and the helper `civitai_download.sh` exists, this script will attempt
#   a direct aria2c/curl/wget download first, and fall back to an API+jq selection method if that fails.

set -euo pipefail

DEST=""
SKIP_CUSTOM=0
SKIP_IPADAPTER=0
SKIP_WAN=0
SKIP_CIVITAI=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    --skip-custom) SKIP_CUSTOM=1; shift;;
    --skip-ipadapter) SKIP_IPADAPTER=1; shift;;
    --skip-wan) SKIP_WAN=1; shift;;
    --skip-civitai) SKIP_CIVITAI=1; shift;;
    --help|-h) echo "Usage: $0 [--dest <path>] [--skip-custom] [--skip-ipadapter] [--skip-wan] [--skip-civitai]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# Choose destination: default to local container ComfyUI path
# In local GPU-only setups there is no network volume mounted, so
# prefer the container path by default. Use `--dest` to override.
if [ -z "$DEST" ]; then
  DEST="/workspace/runpod-slim/ComfyUI"
fi

echo "Preparing ComfyUI content at: $DEST"

# Ensure base folders
mkdir -p "$DEST/models/checkpoints" \
         "$DEST/models/loras" \
         "$DEST/models/vae" \
         "$DEST/models/text_encoders" \
         "$DEST/models/diffusion_models" \
         "$DEST/models/ipadapter" \
         "$DEST/models/clip_vision" \
         "$DEST/custom_nodes" \
         "$DEST/workflows" \
         "$DEST/input" "$DEST/output" "$DEST/saves"

DOWNLOAD_HELPER="$(dirname "$0")/../fresh/download_asset_gpu.sh"
CPU_HELPER="$(dirname "$0")/../fresh/download_asset_cpu.sh"
CIVI_HELPER=""

has_cmd() { command -v "$1" >/dev/null 2>&1; }

download_url_to() {
  url="$1"; outname="$2"; outdir="$3"
  mkdir -p "$outdir"
  if [ -n "$outname" ] && [ -f "$outdir/$outname" ]; then
    echo "Skipping existing $outdir/$outname"
    return 0
  fi
  if [ -x "$DOWNLOAD_HELPER" ]; then
    "$DOWNLOAD_HELPER" "$url" "$outname" "$outdir" && return 0 || echo "helper failed, falling back"
  fi
  if has_cmd aria2c; then
    if [ -n "$outname" ]; then
      aria2c -x 16 -s 16 -d "$outdir" -o "$outname" "$url" && return 0 || true
    else
      # Let aria2c pick the filename from Content-Disposition when no outname provided
      aria2c -x 16 -s 16 -d "$outdir" --content-disposition "$url" && return 0 || true
    fi
  fi
  if has_cmd curl; then
    if [ -n "$outname" ]; then
      curl -L -o "$outdir/$outname" "$url" && return 0 || true
    else
      # When no explicit output name is provided we want the remote filename
      # (possibly from Content-Disposition). Change directory to the destination
      # so curl -O / -J writes the file into the correct folder instead of
      # the current working directory.
      (cd "$outdir" && curl -L -J -O "$url") && return 0 || true
    fi
  fi
  if has_cmd wget; then
    if [ -n "$outname" ]; then
      wget -O "$outdir/$outname" "$url" && return 0 || true
    else
      wget -P "$outdir" "$url" && return 0 || true
    fi
  fi
  echo "No downloader available or download failed for $url"
  return 1
}

git_clone_or_update() {
  url="$1"; dest="$2"
  if [ -d "$dest/.git" ]; then
    echo "Updating $dest"
    git -C "$dest" pull --ff-only || echo "git pull failed for $dest"
  else
    echo "Cloning $url -> $dest"
    git clone "$url" "$dest" || echo "git clone failed for $url"
  fi
}

if [ "$SKIP_CUSTOM" -eq 0 ]; then
  echo "Installing/updating custom nodes into $DEST/custom_nodes"
  repos=(
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/banodoco/steerable-motion.git"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/willmiao/ComfyUI-Lora-Manager.git"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit.git"
    "https://github.com/liusida/ComfyUI-AutoCropFaces.git"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/ltdrdata/was-node-suite-comfyui"
    "https://github.com/teward/ComfyUI-Helper-Nodes"
    "https://github.com/kaaskoek232/IPAdapterWAN"
    "https://github.com/rslosch/comfyui-nodesweet"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/ltdrdata/was-node-suite-comfyui"
  )
  for r in "${repos[@]}"; do
    name="$(basename "$r" .git)"
    git_clone_or_update "$r" "$DEST/custom_nodes/$name"
  done
fi

if [ "$SKIP_IPADAPTER" -eq 0 ]; then
  echo "Installing IPAdapterWAN and ip-adapter.bin"
  git_clone_or_update "https://github.com/kaaskoek232/IPAdapterWAN.git" "$DEST/custom_nodes/IPAdapterWAN"
  IPBIN_URL="https://huggingface.co/InstantX/SD3.5-Large-IP-Adapter/resolve/main/ip-adapter.bin"
  download_url_to "$IPBIN_URL" "ip-adapter.bin" "$DEST/models/ipadapter"
  echo "Installing sigclip_vision_384 into $DEST/models/clip_vision/sigclip_vision_384"
  git_clone_or_update "https://huggingface.co/Comfy-Org/sigclip_vision_384" "$DEST/models/clip_vision/sigclip_vision_384"
  # If git-lfs present, try pulling LFS objects
  if has_cmd git-lfs && [ -d "$DEST/models/clip_vision/sigclip_vision_384" ]; then
    (cd "$DEST/models/clip_vision/sigclip_vision_384" && git lfs pull) || true
  fi
fi

if [ "$SKIP_WAN" -eq 0 ]; then
  echo "Downloading Wan_2.2 repackaged assets"
  HF_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
  files=(
    "diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|models/diffusion_models"
    "diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|models/diffusion_models"
    "vae/wan_2.1_vae.safetensors|models/vae"
    "loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|models/loras"
    "loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors|models/loras"
    "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|models/text_encoders"
  )
  for pair in "${files[@]}"; do
    rel="${pair%%|*}"
    sub="${pair##*|}"
    url="$HF_BASE/$rel"
    outdir="$DEST/$sub"
    outname="$(basename "$rel")"
    download_url_to "$url" "$outname" "$outdir" || echo "Failed to download $rel"
  done
fi

if [ "$SKIP_CIVITAI" -eq 0 ]; then
  echo "Downloading requested Civitai models/loras via direct aria2c API (IDs: 1820829, 2070335)"
  if [ -z "${CIVITAI_TOKEN:-}" ]; then
    echo "CIVITAI_TOKEN not set; skipping Civitai direct downloads. Export CIVITAI_TOKEN to enable."
  else
    # List of civitai downloads: model_id|out_subdir|out_name
    civlist=(
      "2060527|models/checkpoints|Wan2.2_I2V_A14B.gguf"
      "2303105|models/loras|WAN_DR34ML4Y_All-In-One_NSFW_high.safetensors"
      "2303113|models/loras|WAN_DR34ML4Y_All-In-One_NSFW_low.safetensors"
      "2342652|models/loras|WAN_2.2_I2V_POV_Paizuri_Titfuck_high.safetensors"
      "2342660|models/loras|WAN_2.2_I2V_POV_Paizuri_Titfuck_low.safetensors"
    )
    for entry in "${civlist[@]}"; do
      model_id="${entry%%|*}"
      rest="${entry#*|}"
      out_sub="${rest%%|*}"
      out_name="${rest#*|}"
      outdir="$DEST/$out_sub"
      mkdir -p "$outdir"
      if [ -f "$outdir/$out_name" ]; then
        echo "Skipping existing $outdir/$out_name"
        continue
      fi
      direct_url="https://civitai.com/api/download/models/${model_id}?token=${CIVITAI_TOKEN}"
      echo "aria2c -c -d '$outdir' --content-disposition -x 16 -s 16 -o '$out_name' '$direct_url'"
      if command -v aria2c &>/dev/null; then
        aria2c -c -d "$outdir" --content-disposition -x 16 -s 16 -o "$out_name" "$direct_url" || echo "aria2c failed for model $model_id"
      else
        echo "aria2c not found; attempting curl fallback"
        curl -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" -o "$outdir/$out_name" "$direct_url" || echo "curl failed for model $model_id"
      fi
    done
  fi
fi

echo "GPU setup complete. Summary of directories under $DEST:"
du -sh "$DEST/models" || true
du -sh "$DEST/custom_nodes" || true

echo "Done. Restart ComfyUI to pick up new custom nodes/models (or re-link volume)."

exit 0

