# Shell environment for the GPU toolchain baked into this image. Sourced by login shells
# (/etc/profile.d) and by /root/.bashrc, so SSH sessions and `ssh host 'cmd'` both get it.
case ":$PATH:" in *":/opt/node/bin:"*) ;; *) export PATH="/opt/node/bin:/opt/ffmpeg/bin:/opt/blender:$PATH" ;; esac
export NVIDIA_DRIVER_CAPABILITIES=all
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
# The NVIDIA container runtime injects the Vulkan ICD when the driver capabilities include graphics.
# Pin the loader to it so Chrome/ANGLE never picks a software (lavapipe) device.
if [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
elif [ -f /etc/vulkan/icd.d/nvidia_icd.json ]; then
  export VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
fi
