# Alyx on BC-250: GoW WiVRn base + bc250 Vulkan H.264 overlay
#
# Base already has: WiVRn 26.9 + Steam in gamescope + xrizer + OpenComposite
# This overlay adds ONLY the BC-250 VA-API driver + shaders + WiVRn tuning.
#
# Build:  podman build -f Containerfile -t wivrn-alyx:bc250 .
# Run:    ./run.sh  (or see README.md)
#
# Multi-stage: builder compiles the driver, final image copies only the
# driver + shaders. Build tools (cmake/gcc) do NOT end up in the final image,
# so the overlay stays ~20-50 MB instead of +300-500 MB.

# ---------- Stage 1: build bc250 driver ----------
FROM fedora:44 AS builder

ARG BC250_VERSION=v0.3.0

RUN dnf install -y --setopt=install_weak_deps=False \
      git cmake ninja-build gcc-c++ pkgconf \
      vulkan-headers vulkan-loader-devel \
      libva-devel libdrm-devel mesa-libGL-devel \
    && dnf clean all

RUN git clone --depth 1 --branch ${BC250_VERSION} \
      https://github.com/simpmix/bc250-encoding-decoding-fix.git /tmp/bc250 \
    && cmake -S /tmp/bc250/approach1-compute-encoder -B /tmp/bc250/build \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --build /tmp/bc250/build -j$(nproc) \
    && DESTDIR=/tmp/bc250-install cmake --install /tmp/bc250/build \
    && ls -lh /tmp/bc250-install/usr/lib64/dri/bc250_drv_video.so \
    && ls -lh /tmp/bc250-install/usr/share/bc250/shaders | head

# ---------- Stage 2: GoW WiVRn base + driver overlay ----------
# Pin by digest in production — :edge floats. Get the digest with:
#   podman images --digests ghcr.io/baz00k/gow-collection/wivrn:edge
FROM ghcr.io/baz00k/gow-collection/wivrn:edge

USER root

# Runtime libs the bc250 driver needs (no build tools here)
RUN dnf install -y --setopt=install_weak_deps=False \
      libgomp libva vulkan-loader libdrm \
      libva-utils ffmpeg \
    && dnf clean all

# Copy ONLY the installed driver + shaders from the builder
COPY --from=builder /tmp/bc250-install/usr/lib64/dri/bc250_drv_video.so /usr/lib64/dri/bc250_drv_video.so
COPY --from=builder /tmp/bc250-install/usr/share/bc250/ /usr/share/bc250/

# WiVRn config — VA-API, H.264
# 2HW + 1SW topology: left/right eye via HW VA-API, alpha/foveation via SW.
# See docs/wivrn-guide.md in the bc250 repo for the preset this mirrors.
COPY wivrn-config.json /etc/wivrn/config.json
COPY wivrn-config.json /home/retro/.config/wivrn/config.json
RUN chown retro:retro /home/retro/.config/wivrn/config.json || true

# BC-250 WiVRn env — from bc250 docs/wivrn-guide.md
# SLICES=2 for VR (not 4) to avoid thread over-subscription across 2 encoders.
# FAST_MODE=1 keeps GPU compute <3-5% so Alyx keeps its CUs.
# OMP/GOMP vars are critical — without them idle slice threads spin at ~1300% CPU.
# H264_BACKEND=x264 = Zen 2 CPU offload, leaves GPU free for Alyx rendering.
# Switch to `compute` only if CPU becomes the bottleneck.
ENV LIBVA_DRIVER_NAME=bc250
ENV BC250_FAST_MODE=1
ENV BC250_SLICES_PER_FRAME=2
ENV BC250_H264_BACKEND=x264
ENV OMP_WAIT_POLICY=PASSIVE
ENV GOMP_SPINCOUNT=0
ENV OMP_NUM_THREADS=2

USER retro
# Inherit CMD from base — gamescope + Steam + WiVRn startup
