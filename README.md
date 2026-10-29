# runpod-gpu-image

A ready-to-work GPU pod image for [Runpod](https://www.runpod.io/). It extends Runpod's official
PyTorch image (CUDA 13.2, PyTorch 2.13, Ubuntu 24.04) with the tools a 3D rendering, video and
browser-capture job needs, so a pod is usable the moment SSH comes up instead of after ten minutes
of downloads.

```
ghcr.io/trenbolone1122/runpod-gpu-image:latest
```

One-click on Runpod: [Deploy the public template](https://console.runpod.io/deploy?template=5v7v7rzo6n)
("GPU Render Workstation (Blender, FFmpeg NVENC, Chrome, Node)", pinned to a versioned tag,
50 GB container disk, 50 GB volume disk at `/workspace`, SSH and JupyterLab, CUDA 13.2+ hosts).

## What is inside

| Component | Version | Where | Notes |
|---|---|---|---|
| Base | `runpod/pytorch:1.5.0-cu1320-torch2130-ubuntu2404` | | CUDA 13.2, PyTorch 2.13.0, Python 3.10 to 3.13 (3.12 default), uv, sshd and Jupyter via `/start.sh` |
| Blender | 5.2.3 | `/opt/blender`, `blender` on PATH | Cycles with OptiX and CUDA; EEVEE works under `xvfb-run` |
| FFmpeg | 8.1.3 (BtbN static GPL build, 2026-10-28) | `/opt/ffmpeg`, `ffmpeg` and `ffprobe` on PATH | h264/hevc/av1 NVENC, NVDEC, libx264, libx265. Not 9.0: its NVENC API 13.1 needs driver 610+, Runpod hosts run 595.x |
| Google Chrome | stable at build time | `google-chrome`, wrapper `chrome-gpu` | headless on the GPU through ANGLE/Vulkan for WebGL and WebGPU capture; no X server needed |
| Node.js | 26.13.0 LTS | `/opt/node`, `node` `npm` `npx` on PATH | |
| playwright-core | 1.64.1 | `playwright-core` on PATH | drives the system Chrome (`channel: "chrome"`); no bundled browsers |
| hf CLI | latest huggingface_hub with hf_transfer | `hf` on PATH | fast model downloads |
| Xvfb, Vulkan and EGL runtime | Ubuntu 24.04 packages | | `vulkan-tools`, `mesa-utils`, every shared library Chrome needs |
| Shell tools | | | tmux, rsync, git, jq, unzip, 7z, xz, htop |
| `gpu-smoke` | | `/usr/local/bin/gpu-smoke` | PASS/FAIL check of all of the above on the pod's GPU |

Not included on purpose: Python model stacks such as vLLM or TTS packages. They are several GB
each and move weekly, so they belong in a `uv venv` on the pod's network volume (`uv` is in the
image, and the base image already points `UV_CACHE_DIR` at `/workspace/.cache/uv`).

## Using it on Runpod

The image needs a host whose driver supports CUDA 13.2. In the Runpod console pick a GPU that
lists CUDA 13.2 under the filter, or through the REST API set `gpu.minCudaVersion` to `"13.2"`:

```json
{
  "name": "render",
  "image": "ghcr.io/trenbolone1122/runpod-gpu-image:latest",
  "cloud": "SECURE",
  "gpu": {"id": "NVIDIA RTX A5000", "count": 1, "minCudaVersion": "13.2"},
  "disk": 50,
  "ports": ["22/tcp"],
  "env": {"PUBLIC_KEY": "ssh-ed25519 AAAA... you@host"}
}
```

`/start.sh` from the base image is still the container command, so `PUBLIC_KEY`, Jupyter and the
usual Runpod template behaviour are unchanged. Once SSH is up:

```bash
gpu-smoke                                                 # everything PASS?
blender -b scene.blend -E CYCLES -o //frames/f_ -f 1 -- --cycles-device OPTIX
ffmpeg -i in.mov -c:v h264_nvenc -preset p5 -cq 19 -c:a aac out.mp4
chrome-gpu --screenshot=/tmp/s.png --window-size=1920,1080 https://example.com
```

Container disk: 50 GB is a comfortable default for render scratch (frames, encodes, Chrome
profile). Put scenes, outputs and model weights on a network volume mounted at `/workspace` so
they survive the pod.

## Tags

| Tag | Meaning |
|---|---|
| `latest` | most recent build of `main` |
| `YYYY.MM.DD` | the build of `main` on that day |
| `1.2.3` | build of git tag `v1.2.3` |
| `sha-abc1234` | build of that commit |

Pin a dated or versioned tag in anything automated; `latest` moves.

## Building

Every push to `main` and every `v*` tag runs `.github/workflows/build.yml`, which builds the
Dockerfile on a GitHub-hosted runner and pushes to GHCR with the repository's own `GITHUB_TOKEN`.
No secrets to configure. A build takes about 7 to 10 minutes; the result is 11.4 GB compressed,
of which the base image is 10.3 GB.

Versions are build args at the top of the Dockerfile. To bump one, change the version and the
matching checksum (Node: `SHASUMS256.txt` on nodejs.org; Blender: the `.md5` file next to the
release; FFmpeg: `checksums.sha256` on the BtbN release), push, and pull the new tag.

Local build, if you have Docker and about 40 GB free:

```bash
docker build -t runpod-gpu-image .
```

## Licences

The Dockerfile and scripts in this repository are MIT. The image also contains third-party
software under its own terms: Blender (GPL), FFmpeg (GPL build by BtbN), Node.js (MIT), Google
Chrome (downloaded at build time under Google's terms of service), NVIDIA CUDA libraries from the
base image (NVIDIA EULA) and Ubuntu packages.
