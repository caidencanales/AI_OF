# bm-studio Wan worker — SLIM image
#
# Key change vs the previous attempt: no model baking. The base setup (ComfyUI +
# pinned custom nodes + crt-nodes LTX23 patch) ships in the image (~12 GB
# total), and models come from the existing network volume `7vcztvwvl6` at
# /runpod-volume — mounted on the serverless endpoint config.
#
# Why no models in the image:
# GitHub-hosted free runner has ~14 GB free disk. A single 32 GB Wan model
# RUN command produces an intermediate state too large to fit. Buildx with
# registry-cache only frees disk AFTER a layer commits — so any single
# layer larger than free disk fails the build.
#
# Worker boot (after this image lands in GHCR + endpoint reconfigured):
#   1. Image pull from GHCR (~12 GB — first-time on host ~3 min, FlashBoot ~30s after)
#   2. dockerArgs runs worker_r2_startup.py with SKIP_R2_DOWNLOAD=1
#      → script symlinks /comfyui/models → /runpod-volume/runpod-slim/ComfyUI/models
#      → custom nodes already in image (no copy needed)
#   3. ComfyUI starts with everything available; no R2 download
#   4. Fits the boot deadline cleanly

FROM runpod/worker-comfyui:5.5.0-base

ENV PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive

# === Layer 1: rarely-changing system packages ===
RUN apt-get update && apt-get install -y --no-install-recommends \
        rclone ffmpeg git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# === Layer 2: custom node clones (pinned to SHA) ===
WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
        && cd ComfyUI-WanVideoWrapper && git checkout e4e7f41 && cd .. \
    && git clone https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git \
    && git clone https://github.com/kijai/ComfyUI-KJNodes.git \
        && cd ComfyUI-KJNodes && git checkout 7967a94 && cd .. \
    && git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    && git clone https://github.com/digitaljohn/comfyui-propost.git \
    && git clone https://github.com/kijai/ComfyUI-segment-anything-2.git \
    && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    && git clone https://github.com/yolain/ComfyUI-Easy-Use.git \
    && git clone https://github.com/PGCRT/CRT-Nodes.git crt-nodes \
    && git clone https://github.com/rgthree/rgthree-comfy.git \
    && find . -maxdepth 2 -name '.git' -type d -exec rm -rf {} + 2>/dev/null || true

# === Layer 3: patch crt-nodes LTX23 imports (gate the broken import) ===
COPY patch_crt_nodes.py /tmp/patch_crt_nodes.py
RUN python3 /tmp/patch_crt_nodes.py && rm /tmp/patch_crt_nodes.py

LABEL org.bm-studio.image="wan-animate-slim-no-models"
LABEL org.bm-studio.built="2026-05-09"
LABEL org.bm-studio.wan-sha="e4e7f41"
LABEL org.bm-studio.kj-sha="7967a94"
LABEL org.bm-studio.notes="Models live on network volume 7vcztvwvl6 (US-GA-2). Endpoint must mount it at /runpod-volume + run worker_r2_startup.py with SKIP_R2_DOWNLOAD=1."

# Default to the base image's CMD/ENTRYPOINT (worker-comfyui handler)
