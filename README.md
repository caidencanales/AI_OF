# bm-studio Wan image — GitHub Actions builder

Builds the production image and pushes to `ghcr.io/<your-username>/bm-studio-wan:v1`. Runs on GitHub's free Linux runner (Buildx with registry-cache so the 50 GB image fits the runner's 14 GB free disk).

## What gets built

A 50 GB image with all of this baked in:

- `runpod/worker-comfyui:5.5.0-base` (ComfyUI + RunPod serverless handler)
- 10 custom nodes pinned to their working SHAs (KJNodes @ `7967a94`, WanVideoWrapper @ `e4e7f41`, etc.)
- `crt-nodes` with the LTX23 import gate patch baked in
- Wan 14B animate model (32 GB)
- UMT5 text encoder (10.5 GB)
- VAE, CLIP-vision, SAM2, ViTPose, YOLO

LoRAs are NOT baked — they stay on R2 and the worker fetches them at handler init.

## Setup (one-time, ~5 min)

### 1. Create a private GitHub repo

Name it whatever you want — recommended `bm-studio-image`. Make it **private**. Don't initialize with a README (we have one already).

### 2. Add 5 R2 secrets

Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Add each of these (values are in your local `.env`):

| Name | Value |
|---|---|
| `R2_ACCOUNT_ID` | `09e942b8e20e44a6cf075a6000cd0a64` |
| `R2_ENDPOINT` | `https://09e942b8e20e44a6cf075a6000cd0a64.r2.cloudflarestorage.com` |
| `R2_BUCKET_NAME` | `aiinfluncers` |
| `R2_ACCESS_KEY_ID` | `ed1811c66f3fca2dd704643a757cffeb` |
| `R2_SECRET_ACCESS_KEY` | (the 64-char secret in your `.env`) |

### 3. Push the files

Two options:

**Option A — git CLI (Windows PowerShell):**

```powershell
cd C:\bm-studio\bm-studio\_system\docker\github-actions-build
git init
git branch -M main
git add .
git commit -m "Initial: bm-studio Wan image builder"
git remote add origin https://github.com/<your-username>/bm-studio-image.git
git push -u origin main
```

**Option B — web upload:**

1. On the new repo's page, click **Add file** → **Upload files**
2. Drag the contents of `C:\bm-studio\bm-studio\_system\docker\github-actions-build\` into the upload zone (Dockerfile, patch_crt_nodes.py, .github folder)
3. Commit directly to `main`

### 4. Run the workflow

Pushing to `main` triggers it automatically. Or:

- Repo → **Actions** tab → **Build bm-studio Wan image** → **Run workflow** → tag `v1` → green button

The first run takes ~30–60 min (downloads 50 GB of models from R2 inside GitHub's network, builds layers, streams to GHCR cache, finally pushes the production tag). Subsequent rebuilds (e.g., new Wan version) reuse the cache and run in 5–15 min.

## After build completes

The image is at:

```
ghcr.io/<your-username>/bm-studio-wan:v1
```

Tell me (Claude) when it's pushed and I'll wire it into the RunPod serverless endpoint template — one GraphQL `saveTemplate` call points the existing endpoint at the new image, and we're done.

## Cost

Free for our use case:
- GitHub-hosted runner: 2,000 free minutes/month on private repos (we'll use ~60–90)
- GHCR storage: free for private packages of any size
- Network egress (image pull from RunPod workers): free between RunPod ↔ GHCR

Total ongoing cost: **$0/month for the image itself**. Inference cost is unchanged.

## Why this works where RunPod-side builds didn't

GitHub Actions runners are full Linux VMs with Docker pre-installed and a real systemd. Docker-in-Docker just works there. RunPod's serverless containers don't run systemd, so `dockerd` can't start the same way — that's why our two prior attempts (DinD then kaniko) failed.

The Buildx registry-cache trick (`cache-to=type=registry,mode=max`) is the key to fitting a 50 GB image build on a runner with only ~14 GB free disk: each layer is uploaded to the GHCR cache image as soon as it's built, and the local copy can be evicted before the next layer.
