# syntax=docker/dockerfile:1
# GPU workstation image for Runpod pods.
#
# Base: Runpod's official PyTorch image (CUDA 13.2, PyTorch 2.13, Python 3.10 to 3.13 with 3.12 as
# default, uv, Ubuntu 24.04). Its /start.sh starts sshd from the PUBLIC_KEY env var and Jupyter,
# so nothing about pod startup changes. This file only adds the render and capture toolchain:
#
#   Blender (Cycles OptiX/CUDA, EEVEE under Xvfb)      /opt/blender, `blender` on PATH
#   FFmpeg static GPL build with NVENC/NVDEC            /opt/ffmpeg,  `ffmpeg` `ffprobe` on PATH
#   Google Chrome stable + Xvfb + Vulkan/EGL runtime   `chrome-gpu` wrapper for GPU WebGL/WebGPU capture
#   Node.js LTS + playwright-core                       /opt/node,    `node` `npm` `npx` `playwright-core` on PATH
#   hf CLI with hf_transfer                             `hf` on PATH (model downloads)
#   gpu-smoke                                           PASS/FAIL check of everything above on the GPU
#
# Build args pin every version; checksums come from each project's published checksum list.
# Python model stacks (vLLM, TTS and similar) are not baked in: they are several GB each and change
# weekly, so they belong in a uv venv on the pod's network volume.

ARG BASE_IMAGE=runpod/pytorch:1.5.0-cu1320-torch2130-ubuntu2404
FROM ${BASE_IMAGE}

ARG NODE_VERSION=26.13.0
ARG NODE_SHA256=d28a96af6c38596f6d9d97c0ee531c13d238d757742387d1928de822d959e997
ARG PLAYWRIGHT_CORE_VERSION=1.64.1
ARG BLENDER_VERSION=5.2.3
ARG BLENDER_MD5=46fcccf0d7404698ecea8d205923235e
ARG FFMPEG_RELEASE=autobuild-2026-10-28-19-47
ARG FFMPEG_ASSET=ffmpeg-n9.0.2-37-gae19868753-linux64-gpl-9.0.tar.xz
ARG FFMPEG_SHA256=d5824906a9f3cae531f9f8b830b20fe51e7a422d8ed6fcdef3be4d5209b1b0a1

LABEL org.opencontainers.image.source="https://github.com/trenbolone1122/runpod-gpu-image" \
      org.opencontainers.image.description="Runpod pod image: Blender, FFmpeg NVENC, Chrome GPU capture, Node.js, Playwright on CUDA 13.2 / PyTorch 2.13 / Ubuntu 24.04" \
      org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_DRIVER_CAPABILITIES=all

# 1. System libraries (Ubuntu 24.04 package names): OpenGL/EGL/Vulkan runtime, X virtual framebuffer,
#    every shared library Chrome needs, shell tools. The base already ships git, rsync, curl, wget,
#    openssh-server and nano.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git rsync tmux htop jq unzip p7zip-full xz-utils less file \
      libgl1 libegl1 libgles2 libglvnd0 libglx0 libopengl0 libvulkan1 vulkan-tools mesa-utils \
      xvfb xauth x11-utils x11-xserver-utils \
      libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 libice6 libxshmfence1 libxss1 \
      libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 libxcomposite1 libxdamage1 libxrandr2 \
      libgbm1 libasound2t64 libpangocairo-1.0-0 libgtk-3-0t64 libu2f-udev fonts-liberation fonts-noto-color-emoji \
      libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# 2. Google Chrome stable. Google publishes one unversioned .deb and no checksum; apt resolves its
#    dependencies. Used headless on the GPU through ANGLE/Vulkan (see bin/chrome-gpu).
RUN curl -fsSL --retry 3 -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && rm -rf /tmp/chrome.deb /var/lib/apt/lists/* \
    && google-chrome --version

# 3. Node.js LTS from the official tarball, checksum from nodejs.org SHASUMS256.txt, plus playwright-core
#    (drives the system Chrome; no bundled browsers are downloaded).
RUN curl -fsSL --retry 3 -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/node && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 && rm /tmp/node.tar.xz
ENV PATH=/opt/node/bin:${PATH}
RUN npm install -g "playwright-core@${PLAYWRIGHT_CORE_VERSION}" && npm cache clean --force && node -v && playwright-core --version

# 4. Blender, official tarball (download.blender.org, mirror fallback), md5 from the release's .md5 list.
RUN f="blender-${BLENDER_VERSION}-linux-x64.tar.xz"; d="Blender${BLENDER_VERSION%.*}"; \
    (curl -fsSL --retry 3 -o "/tmp/$f" "https://download.blender.org/release/$d/$f" \
      || curl -fsSL --retry 3 -o "/tmp/$f" "https://mirrors.ocf.berkeley.edu/blender/release/$d/$f") \
    && echo "${BLENDER_MD5}  /tmp/$f" | md5sum -c - \
    && mkdir -p /opt/blender && tar -xJf "/tmp/$f" -C /opt/blender --strip-components=1 && rm "/tmp/$f" \
    && ln -s /opt/blender/blender /usr/local/bin/blender \
    && blender --version

# 5. FFmpeg static GPL build with NVENC/NVDEC (BtbN FFmpeg-Builds, dated autobuild release, sha256 from
#    that release's checksums.sha256). Symlinked into /usr/local/bin ahead of any distro ffmpeg.
RUN curl -fsSL --retry 3 -o /tmp/ffmpeg.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/download/${FFMPEG_RELEASE}/${FFMPEG_ASSET}" \
    && echo "${FFMPEG_SHA256}  /tmp/ffmpeg.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/ffmpeg && tar -xJf /tmp/ffmpeg.tar.xz -C /opt/ffmpeg --strip-components=1 && rm /tmp/ffmpeg.tar.xz \
    && ln -sf /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg && ln -sf /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe \
    && ffmpeg -hide_banner -version | sed -n 1p && ffmpeg -hide_banner -encoders | grep h264_nvenc >/dev/null

# 6. hf CLI (huggingface_hub with hf_transfer) as a uv tool. uv ships in the base image at /bin/uv;
#    the base points UV_CACHE_DIR at /workspace, which does not exist at build time, so use /tmp here.
RUN UV_CACHE_DIR=/tmp/uv-cache UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
      uv tool install --python 3.12 "huggingface_hub[cli,hf_transfer]" \
    && rm -rf /tmp/uv-cache && hf --help >/dev/null

# 7. Helpers and shell environment: chrome-gpu, gpu-smoke, and a profile.d file that puts the tools on
#    PATH for login shells and picks the NVIDIA Vulkan ICD so Chrome never falls back to a software renderer.
COPY bin/chrome-gpu bin/gpu-smoke /usr/local/bin/
COPY etc/gpu-tools.sh /etc/profile.d/gpu-tools.sh
RUN set -e; chmod 755 /usr/local/bin/chrome-gpu /usr/local/bin/gpu-smoke /etc/profile.d/gpu-tools.sh; \
    grep -qs 'profile.d/gpu-tools.sh' /root/.bashrc || echo '. /etc/profile.d/gpu-tools.sh' >> /root/.bashrc

ENV __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json

# CMD and ENTRYPOINT are inherited from the base image: /opt/nvidia/nvidia_entrypoint.sh then /start.sh.
