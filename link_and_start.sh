#!/usr/bin/env bash
# link_and_start.sh
# Link the volume into the container ComfyUI path and start ComfyUI (/start.sh).
# Usage: link_and_start.sh [volume_path] [comfy_dir]

set -euo pipefail

VOL_DIR="${1:-/runpod-volume/ComfyUI}"
COMFY_DIR="${2:-/workspace/runpod-slim/ComfyUI}"

echo "Linking $VOL_DIR -> $COMFY_DIR"

replace_with_symlink() {
  local target_dir="$1" link_dir="$2"

  # ensure target exists
  mkdir -p "$target_dir"

  # if link already exists and is symlink, remove it
  if [ -L "$link_dir" ]; then
    rm -f "$link_dir"
  fi

  # If a real directory exists at link_dir, attempt to preserve its contents by
  # moving them into the target_dir when target_dir is empty. Otherwise skip to avoid data loss.
  if [ -d "$link_dir" ] && [ ! -L "$link_dir" ]; then
    # enable dotglob so hidden files are moved too
    bash -c 'shopt -s dotglob nullglob; files=("" )'
    shopt -s dotglob nullglob
    files=("$link_dir"/*)
    shopt -u dotglob nullglob

    if [ -n "${files[0]:-}" ]; then
      # only move if target_dir is empty
      if [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
        echo "Moving existing contents of $link_dir into $target_dir"
        # create target and move contents
        mkdir -p "$target_dir"
        shopt -s dotglob nullglob
        mv "$link_dir"/* "$target_dir" 2>/dev/null || cp -a "$link_dir"/. "$target_dir" 2>/dev/null
        shopt -u dotglob nullglob
        rm -rf "$link_dir"
      else
        echo "Warning: $link_dir exists and $target_dir is not empty — skipping symlink to avoid overwrite"
        return 0
      fi
    else
      # empty dir: remove and create symlink
      rm -rf "$link_dir"
    fi
  fi

  mkdir -p "$(dirname "$link_dir")"
  ln -s "$target_dir" "$link_dir"
  echo "Linked $link_dir -> $target_dir"
}

# Ensure volume subfolders exist
mkdir -p "$VOL_DIR/models" "$VOL_DIR/models/checkpoints" "$VOL_DIR/models/loras" "$VOL_DIR/models/vae" "$VOL_DIR/models/text_encoders" "$VOL_DIR/models/diffusion_models" \
         "$VOL_DIR/custom_nodes" "$VOL_DIR/workflows" "$VOL_DIR/input" "$VOL_DIR/output" "$VOL_DIR/saves"

# Ensure container comfy dir exists
mkdir -p "$COMFY_DIR"

replace_with_symlink "$VOL_DIR/models" "$COMFY_DIR/models"
replace_with_symlink "$VOL_DIR/custom_nodes" "$COMFY_DIR/custom_nodes"
replace_with_symlink "$VOL_DIR/workflows" "$COMFY_DIR/user/default/workflows"
replace_with_symlink "$VOL_DIR/input" "$COMFY_DIR/input"
replace_with_symlink "$VOL_DIR/output" "$COMFY_DIR/output"
replace_with_symlink "$VOL_DIR/saves" "$COMFY_DIR/saves"

echo "Symlink summary for $COMFY_DIR:"
ls -la "$COMFY_DIR" || true

echo "Starting container start script (/start.sh) if present..."
if [ -x "/start.sh" ]; then
  exec /start.sh
else
  echo "/start.sh not found — start ComfyUI manually or create /start.sh"
  exit 0
fi
