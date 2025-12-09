# RunPod ComfyUI - Fresh v2 workflow

Purpose
- Provide a minimal, reliable, volume-first workflow that you can run from a CPU instance to prepare storage, then attach the same volume to GPU pods quickly.

Principles
- Keep actions explicit and idempotent.
- Prefer in-pod downloads into the volume (avoids reuploading large files).
- Provide a small local sync helper for convenience.

Files
- `init_volume.sh` — create the directory layout and minimal permissions (Ubuntu friendly).
- `download_asset_cpu.sh` — downloader intended for the CPU/Ubuntu setup phase. Includes instructions for installing `aria2`.
- `download_asset_gpu.sh` — downloader intended for GPU pods; uses higher concurrency with `aria2c` when available.
- `sync_local.sh` — optional helper (local machine) to push a folder into the volume via `runpodctl`.
- `link_and_start.sh` — idempotent symlink creation from ComfyUI path to volume and start the original container start script.

Workflow (short)
1. Boot a small CPU pod and mount your persistent volume at `/runpod-volume`.
2. Copy `runpod-scripts/fresh/*` into `/runpod-volume/ComfyUI/` and `chmod +x` them.
3. Run `init_volume.sh` then use `download_asset_cpu.sh` (on the CPU instance) or `runpodctl send` to place models/loras/workflows into `/runpod-volume/ComfyUI`.
	 - Example token export lines (replace placeholders before running):
		 ```bash
		 export CIVITAI_TOKEN="your_civitai_token_here"
		 export HF_TOKEN="your_hf_token_here"
		 ```
	 - Use `download_asset_gpu.sh` when you are on a GPU pod and want faster concurrent downloads.
4. Attach the same volume to any GPU pod and use `link_and_start.sh` (or set Docker Command to run it) to start ComfyUI with the volume content.

If you want, the scripts can be extended to automatically download a canonical list of models on the first run.
