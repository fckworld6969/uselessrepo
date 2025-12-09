#!/usr/bin/env bash
# init_volume.sh — create persistent folder layout for ComfyUI on a volume
# Usage: init_volume.sh [volume_path]
#
# Designed to be run on Ubuntu (CPU instance) during initial volume setup.
# If `aria2c` is missing this script will offer guidance to install it (requires sudo).

set -euo pipefail

VOL_DIR="${1:-/runpod-volume/ComfyUI}"

echo "Initializing volume: $VOL_DIR"

mkdir -p "$VOL_DIR/models/checkpoints" \
                 "$VOL_DIR/models/loras" \
                 "$VOL_DIR/models/vae" \
                 "$VOL_DIR/models/text_encoders" \
                 "$VOL_DIR/models/diffusion_models" \
                 "$VOL_DIR/custom_nodes" \
                 "$VOL_DIR/workflows" \
                 "$VOL_DIR/input" \
                 "$VOL_DIR/output" \
                 "$VOL_DIR/saves"

# Set permissive group-writable permissions so other containers/users can write
umask 0002 || true
chmod -R g+rwX "$VOL_DIR"

echo "Volume initialized and writable by group."
echo "Paths created under: $VOL_DIR"

# --- Optional: install IPAdapterWAN and required models ---
# Controlled by env var: INSTALL_IPADAPTER (default: 1 = enabled)
if [ "${INSTALL_IPADAPTER:-1}" != "0" ]; then
    echo "\n[IPAdapter] INSTALL_IPADAPTER enabled — installing IPAdapterWAN and models into the volume"

    # Ensure git is available (attempt to install if running as root on Ubuntu)
    if ! command -v git &>/dev/null; then
        echo "git not found."
        if [ "${INSTALL_APT_PACKAGES:-0}" = "1" ] && [ "$(id -u)" -eq 0 ]; then
            echo "Installing git via apt..."
            apt update && apt install -y git || echo "apt git install failed"
        else
            echo "Please install git (sudo apt install -y git) to allow cloning IPAdapterWAN"
        fi
    fi

    # 1) Clone IPAdapterWAN into custom_nodes if not present
    IPNODE_DIR="$VOL_DIR/custom_nodes/IPAdapterWAN"
    if [ -d "$IPNODE_DIR/.git" ]; then
        echo "IPAdapterWAN already cloned — attempting to pull latest changes"
        git -C "$IPNODE_DIR" pull --ff-only || echo "git pull failed; leaving existing copy"
    else
        echo "Cloning IPAdapterWAN into $IPNODE_DIR"
        git clone https://github.com/kaaskoek232/IPAdapterWAN.git "$IPNODE_DIR" || echo "git clone failed; you can clone manually into $IPNODE_DIR"
    fi

    # 2) Download ip-adapter.bin into models/ipadapter
    mkdir -p "$VOL_DIR/models/ipadapter"
    IPBIN="$VOL_DIR/models/ipadapter/ip-adapter.bin"
    if [ -f "$IPBIN" ]; then
        echo "ip-adapter.bin already exists at $IPBIN — skipping download"
    else
        echo "Downloading ip-adapter.bin to $IPBIN"
        HF_URL="https://huggingface.co/InstantX/SD3.5-Large-IP-Adapter/resolve/main/ip-adapter.bin"
        if command -v aria2c &>/dev/null; then
            if [ -n "${HF_TOKEN:-}" ]; then
                aria2c --header="Authorization: Bearer $HF_TOKEN" -x 4 -s 4 -o "$IPBIN" "$HF_URL" || true
            else
                aria2c -x 4 -s 4 -o "$IPBIN" "$HF_URL" || true
            fi
        else
            if [ -n "${HF_TOKEN:-}" ]; then
                curl -L -H "Authorization: Bearer $HF_TOKEN" -o "$IPBIN" "$HF_URL" || true
            else
                curl -L -o "$IPBIN" "$HF_URL" || true
            fi
        fi
        if [ -f "$IPBIN" ]; then
            echo "Downloaded ip-adapter.bin successfully"
        else
            echo "Failed to download ip-adapter.bin. You can download manually from: $HF_URL (use HF_TOKEN if needed)"
        fi
    fi

    # 3) Clone or update the sigclip vision model repo into models/clip_vision/sigclip_vision_384
    CLIP_DIR="$VOL_DIR/models/clip_vision/sigclip_vision_384"
    if [ -d "$CLIP_DIR/.git" ]; then
        echo "sigclip_vision_384 already present — attempting git pull"
        git -C "$CLIP_DIR" pull --ff-only || echo "git pull for sigclip repo failed"
    else
        echo "Cloning sigclip_vision_384 into $CLIP_DIR"
        # Try a shallow clone; some HuggingFace repos require git-lfs to fetch large files.
        git clone --depth 1 https://huggingface.co/Comfy-Org/sigclip_vision_384 "$CLIP_DIR" || {
            echo "git clone failed — repository may require git-lfs or manual download."
            if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
                echo "git-lfs detected — retrying clone"
                git clone https://huggingface.co/Comfy-Org/sigclip_vision_384 "$CLIP_DIR" || echo "git clone still failed"
                (cd "$CLIP_DIR" && git lfs pull) || true
            else
                echo "If files are missing, install git-lfs (sudo apt install git-lfs) and run:"
                echo "  git clone https://huggingface.co/Comfy-Org/sigclip_vision_384 $CLIP_DIR"
            fi
        }
    fi

    echo "IPAdapter setup completed (or attempted). If any step failed, re-run with appropriate privileges or install missing tools (git, git-lfs, aria2)."
fi

# --- Optional: install/upgrade a curated list of ComfyUI custom nodes ---
# Controlled by env var: INSTALL_CUSTOM_NODES (default: 1 = enabled)
if [ "${INSTALL_CUSTOM_NODES:-1}" != "0" ]; then
    echo "\n[CustomNodes] INSTALL_CUSTOM_NODES enabled — cloning/updating common custom node repos"

    # Prepare arrays of repo URLs and folder names (destination under $VOL_DIR/custom_nodes)
    REPO_URLS=(
        "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
        "https://github.com/yolain/ComfyUI-Easy-Use.git"
        "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
        "https://github.com/cubiq/ComfyUI_essentials.git"
        "https://github.com/banodoco/steerable-motion.git"
        "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
        "https://github.com/willmiao/ComfyUI-Lora-Manager.git"
        "https://github.com/Smirnov75/ComfyUI-mxToolkit.git"
        "https://github.com/liusida/ComfyUI-AutoCropFaces.git"
    )
    REPO_DIRS=(
        "ComfyUI-Custom-Scripts"
        "ComfyUI-Easy-Use"
        "ComfyUI-VideoHelperSuite"
        "ComfyUI_essentials"
        "steerable-motion"
        "ComfyUI-Frame-Interpolation"
        "ComfyUI-Lora-Manager"
        "ComfyUI-mxToolkit"
        "ComfyUI-AutoCropFaces"
    )

    for i in "${!REPO_URLS[@]}"; do
        url="${REPO_URLS[$i]}"
        dir="${REPO_DIRS[$i]}"
        dest="$VOL_DIR/custom_nodes/$dir"

        if [ -d "$dest/.git" ]; then
            echo "Updating $dir"
            git -C "$dest" pull --ff-only || echo "git pull failed for $dir; skipping"
        else
            echo "Cloning $dir into $dest"
            mkdir -p "$(dirname "$dest")"
            git clone "$url" "$dest" || echo "git clone failed for $dir; you can clone manually into $dest"
        fi
    done

    echo "Custom nodes installation attempted. Run a full restart of ComfyUI to load new nodes."
fi

# --- Optional: download Wan 2.2 repackaged assets and related files ---
# Controlled by env var: INSTALL_WAN_MODELS (default: 1 = enabled)
if [ "${INSTALL_WAN_MODELS:-1}" != "0" ]; then
    echo "\n[WanModels] INSTALL_WAN_MODELS enabled — attempting to download Wan_2.2 repackaged files from HuggingFace"

    HF_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"

    # Map of relative paths -> destination subfolders
    declare -A FILE_MAP=(
        ["diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"]="models/diffusion_models"
        ["vae/wan_2.1_vae.safetensors"]="models/
        vae"
        ["loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"]="models/loras"
        ["loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"]="models/loras"
        ["text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"]="models/text_encoders"
    )

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DOWNLOADER="$SCRIPT_DIR/download_asset_cpu.sh"

    for rel in "${!FILE_MAP[@]}"; do
        url="$HF_BASE/$rel"
        dest_sub="${FILE_MAP[$rel]}"
        dest_dir="$VOL_DIR/$dest_sub"
        fname="$(basename "$rel")"

        mkdir -p "$dest_dir"
        if [ -f "$dest_dir/$fname" ]; then
            echo "$fname already exists in $dest_dir — skipping"
            continue
        fi

        echo "Downloading $fname to $dest_dir"
        if [ -x "$DOWNLOADER" ]; then
            "$DOWNLOADER" "$url" "$fname" "$dest_dir" || echo "download_asset_cpu.sh failed for $fname"
        else
            # Fallback: try aria2c/curl directly
            if command -v aria2c &>/dev/null; then
                aria2c -x 8 -s 8 -o "$dest_dir/$fname" "$url" || echo "aria2c failed for $url"
            elif command -v curl &>/dev/null; then
                if [ -n "${HF_TOKEN:-}" ]; then
                    curl -L -H "Authorization: Bearer ${HF_TOKEN}" -o "$dest_dir/$fname" "$url" || echo "curl failed for $url"
                else
                    curl -L -o "$dest_dir/$fname" "$url" || echo "curl failed for $url"
                fi
            else
                echo "No downloader available (aria2c/curl). Install aria2c or curl to fetch $fname"
            fi
        fi
    done

    echo "Wan model fetch attempted. If any files failed, re-run with HF_TOKEN set or download manually."

    # Civitai-sourced items: we have model IDs but automated API download requires more robust handling.
    echo "\n[Civitai] NOTE: The following Civitai model IDs were requested: 1820829, 2070335"
    echo "To download Civitai assets programmatically, export your CIVITAI_TOKEN and run the downloader with the direct civitai URL(s), for example:"
    echo "  export CIVITAI_TOKEN=\"your_token\""
    echo "  ${DOWNLOADER} 'https://civitai.com/models/1820829/download' 'desired_filename.safetensors' '$VOL_DIR/models/checkpoints'"
    echo "If you want, I can add a small helper that queries the Civitai API and downloads matching assets when CIVITAI_TOKEN is present."
fi

# --- Optional: automated Civitai model downloads (guarded) ---
# Controlled by env var: INSTALL_CIVITAI_AUTODOWNLOAD (default: 0 = disabled)
if [ "${INSTALL_CIVITAI_AUTODOWNLOAD:-0}" = "1" ]; then
    if [ -z "${CIVITAI_TOKEN:-}" ]; then
        echo "INSTALL_CIVITAI_AUTODOWNLOAD requested but CIVITAI_TOKEN is not set — skipping Civitai downloads"
    elif command -v "$VOL_DIR/../runpod-scripts/fresh/civitai_download.sh" &>/dev/null || [ -x "$(dirname "${BASH_SOURCE[0]}")/civitai_download.sh" ]; then
        # prefer the local civitai helper we just added
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        CIVI_HELPER="$SCRIPT_DIR/civitai_download.sh"
        if [ ! -x "$CIVI_HELPER" ]; then
            echo "Making civitai helper executable"
            chmod +x "$CIVI_HELPER" || true
        fi

        echo "Running Civitai autodownloads (model IDs: 1820829, 2070335)"
        # Model 1820829: checkpoint (GGUF) and possibly LORA
        "$CIVI_HELPER" "1820829" "Wan2.2 I2V A14B GGUF" "$VOL_DIR/models/checkpoints" || echo "Failed to download checkpoint for 1820829"
        "$CIVI_HELPER" "1820829" "WAN DR34ML4Y - All-In-One NSFW" "$VOL_DIR/models/loras" || echo "Failed to download lora(s) for 1820829"
        # Model 2070335: LORA(s)
        "$CIVI_HELPER" "2070335" "WAN 2.2 I2V - POV Paizuri / Titfuck" "$VOL_DIR/models/loras" || echo "Failed to download lora(s) for 2070335"
    else
        echo "civitai_download.sh not found or not executable — see runpod-scripts/fresh/civitai_download.sh"
    fi
fi

# Ubuntu convenience: suggest installing aria2c for fast downloads if missing
if command -v aria2c &>/dev/null; then
    echo "aria2c is installed — recommended downloader available."
else
    echo "aria2c not found. On Ubuntu you can install it with:"
    echo "  sudo apt update && sudo apt install -y aria2"
    echo "If you want this script to install aria2c automatically, re-run with sudo and set the environment variable INSTALL_ARIA2=1"
    if [ "${INSTALL_ARIA2:-0}" = "1" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            echo "INSTALL_ARIA2 requested but not running as root — re-run with sudo to allow package installation." >&2
        else
            apt update && apt install -y aria2 || echo "apt install failed; please install aria2 manually"
        fi
    fi
fi
