# bm-studio Wan-Animate worker — kaniko-compatible variant
#
# Differences from Dockerfile (BuildKit version):
#   - Replaced `--mount=type=secret` with ARG-based R2 credential passing
#     (kaniko doesn't support BuildKit secrets; uses --build-arg instead).
#   - Final layer wipes rclone config + clears env vars to minimize cred leakage
#     in image history (R2 creds are still rotatable post-build for full safety).
#
# Build:
#   /kaniko/executor --dockerfile=Dockerfile.kaniko --context=. \
#     --destination=ghcr.io/<user>/bm-studio-wan:v1 \
#     --build-arg R2_ACCOUNT_ID=... --build-arg R2_ENDPOINT=... \
#     --build-arg R2_BUCKET_NAME=... --build-arg R2_ACCESS_KEY_ID=... \
#     --build-arg R2_SECRET_ACCESS_KEY=...

FROM runpod/worker-comfyui:5.5.0-base

ENV PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive

# === Layer 1: rarely-changing system packages ===
RUN apt-get update && apt-get install -y --no-install-recommends \
        rclone ffmpeg git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# === Layer 2: rarely-changing custom node clones (pinned to SHA) ===
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

# === ARGs for R2 credentials — passed via kaniko --build-arg ===
ARG R2_ACCOUNT_ID
ARG R2_ENDPOINT
ARG R2_BUCKET_NAME
ARG R2_ACCESS_KEY_ID
ARG R2_SECRET_ACCESS_KEY

# === Layer 4: rclone config (created + used + wiped in single RUN ===
# === Layer 5: text encoder (~10.5 GB) — its own layer ===
RUN mkdir -p /root/.config/rclone /comfyui/models/text_encoders \
    && printf '[r2]\ntype = s3\nprovider = Cloudflare\naccess_key_id = %s\nsecret_access_key = %s\nendpoint = %s\nregion = auto\n' \
        "$R2_ACCESS_KEY_ID" "$R2_SECRET_ACCESS_KEY" "$R2_ENDPOINT" \
        > /root/.config/rclone/rclone.conf \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        /comfyui/models/text_encoders/ --progress --transfers 8 --multi-thread-streams 8

# === Layer 6: VAE + CLIP-vision + SAM2 + detection (~4 GB total) — small layer ===
RUN mkdir -p /comfyui/models/vae /comfyui/models/clip_vision \
                /comfyui/models/sam2 /comfyui/models/detection \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/vae/wan_2_1_vae_bf16.safetensors" \
        /comfyui/models/vae/ --progress --transfers 4 \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/clip_vision/clip_vision_h.safetensors" \
        /comfyui/models/clip_vision/ --progress --transfers 4 \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/sam2/sam2.1_hiera_base_plus.safetensors" \
        /comfyui/models/sam2/ --progress --transfers 4 \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/detection/" \
        /comfyui/models/detection/ --progress --transfers 4

# === Layer 7: WAN 14B (~32 GB) — its own immutable layer ===
# This is the most expensive layer; isolated so handler/code changes don't re-push.
RUN mkdir -p /comfyui/models/diffusion_models \
    && rclone copy "r2:${R2_BUCKET_NAME}/runpod-slim/ComfyUI/models/diffusion_models/wan2.2_animate_14B_bf16.safetensors" \
        /comfyui/models/diffusion_models/ --progress --transfers 16 --multi-thread-streams 16

# === Layer 8: cleanup secrets so they don't ship in the image ===
RUN rm -f /root/.config/rclone/rclone.conf

# === LoRAs are NOT baked. Runtime fetched by handler from R2 ===
# This keeps image size sane and lets us add new character LoRAs without rebuild.

LABEL org.bm-studio.image="wan-animate-baked-kaniko"
LABEL org.bm-studio.built="2026-05-09"
LABEL org.bm-studio.wan-sha="e4e7f41"
LABEL org.bm-studio.kj-sha="7967a94"

# Default to the base image's CMD/ENTRYPOINT (worker-comfyui handler)
