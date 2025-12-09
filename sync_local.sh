#!/usr/bin/env bash
# sync_local.sh — local-machine helper to push a local folder to a RunPod pod volume
# This script assumes `runpodctl` is installed and authenticated on your local machine.
# Usage: sync_local.sh <local_path> <remote_dest_path>

set -euo pipefail

LOCAL_PATH="$1"
REMOTE_PATH="${2:-/runpod-volume/ComfyUI/models/checkpoints}"

if [ -z "$LOCAL_PATH" ] || [ ! -d "$LOCAL_PATH" ]; then
  echo "Usage: sync_local.sh <local_path> <remote_dest_path>"
  echo "Example: sync_local.sh ./models/checkpoints /runpod-volume/ComfyUI/models/checkpoints"
  exit 1
fi

if ! command -v runpodctl &>/dev/null; then
  echo "runpodctl not found. Install runpodctl per RunPod docs and authenticate." >&2
  exit 2
fi

echo "Sending files from $LOCAL_PATH to remote path $REMOTE_PATH"
# runpodctl will interactively ask which pod to use; that's intentional to avoid accidental sends
runpodctl send "$LOCAL_PATH" --dest "$REMOTE_PATH"

echo "Upload requested. Check the pod and move files into the final location if necessary."
