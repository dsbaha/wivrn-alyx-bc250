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
      glslang \
    && dnf clean all

RUN git clone --depth 1 --branch ${BC250_VERSION} \
      https://github.com/simpmix/bc250-encoding-decoding-fix.git /tmp/bc250 \
    && cmake -S /tmp/bc250/approach1-compute-encoder -B /tmp/bc250/build \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --build /tmp/bc250/build -j$(nproc) \
    && DESTDIR=/tmp/bc250-install cmake --install /tmp/bc250/build \
    && test -f /tmp/bc250-install/usr/lib64/dri/bc250_drv_video.so \
    && ls /tmp/bc250-install/usr/share/bc250/shaders/*.spv

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
# Shaders are .spv files compiled by glslangValidator (see builder).
# The driver searches BC250_SHADER_DIR, /usr/share/bc250/shaders,
# /usr/lib64/dri/shaders, and beside the .so — we set the env below too.
COPY --from=builder /tmp/bc250-install/usr/lib64/dri/bc250_drv_video.so /usr/lib64/dri/bc250_drv_video.so
COPY --from=builder /tmp/bc250-install/usr/share/bc250/shaders /usr/share/bc250/shaders

# Headless fix: GoW hardcodes gamescope `--backend wayland`, which means
# "nested inside a host Wayland compositor". Under Wolf, Wolf provides
# that compositor (start_virtual_compositor). On headless Podman / CoreOS
# there is NO host compositor, so gamescope fails with
# "xdg_backend couldn't connect to wayland display".
# Patch gamescope-lib.sh to respect GAMESCOPE_BACKEND (default headless),
# and make wivrn-session.sh create $XDG_RUNTIME_DIR (gamescope needs it
# to exist, and /run/user/<uid> doesn't exist by default in the container).
RUN python3 - <<'PY'
import pathlib
lib = pathlib.Path("/opt/gow/gamescope-lib.sh")
text = lib.read_text()
old = "--backend wayland"
new = '--backend "${GAMESCOPE_BACKEND:-headless}"'
assert old in text, "gamescope-lib.sh no longer contains '--backend wayland' — check upstream"
lib.write_text(text.replace(old, new))
print("Patched gamescope-lib.sh: --backend wayland -> GAMESCOPE_BACKEND (default headless)")

sess = pathlib.Path("/opt/gow/wivrn-session.sh")
stext = sess.read_text()
old2 = 'export XDG_RUNTIME_DIR\n'
new2 = 'export XDG_RUNTIME_DIR\nmkdir -p "$XDG_RUNTIME_DIR"\n'
assert old2 in stext, "wivrn-session.sh no longer contains 'export XDG_RUNTIME_DIR' — check upstream"
sess.write_text(stext.replace(old2, new2, 1))
print("Patched wivrn-session.sh: mkdir -p $XDG_RUNTIME_DIR")
PY

# Default to headless backend for Podman / CoreOS. Override to `wayland`
# only if you run under Wolf (which provides a virtual compositor).
ENV GAMESCOPE_BACKEND=headless
# 2HW + 1SW topology: left/right eye via HW VA-API, alpha/foveation via SW.
# See docs/wivrn-guide.md in the bc250 repo for the preset this mirrors.
# NOTE: Only copy to /etc/wivrn/config.json (system fallback). Do NOT copy to
# /home/retro/... and do NOT USER/chown retro here — the base image has NO
# retro user at build time. Its entrypoint (/opt/gow/entrypoint.sh) creates
# the retro user at RUNTIME from PUID/PGID via gosu, and /home/retro does
# not exist during `podman build`. USER retro / chown retro:retro fails the
# build with "unable to find user retro". Keep the build as root; the
# entrypoint drops to retro at runtime.
COPY wivrn-config.json /etc/wivrn/config.json

# BC-250 WiVRn env — from bc250 docs/wivrn-guide.md
# SLICES=2 for VR (not 4) to avoid thread over-subscription across 2 encoders.
# FAST_MODE=1 keeps GPU compute <3-5% so Alyx keeps its CUs.
# OMP/GOMP vars are critical — without them idle slice threads spin at ~1300% CPU.
# H264_BACKEND=x264 = Zen 2 CPU offload, leaves GPU free for Alyx rendering.
# Switch to `compute` only if CPU becomes the bottleneck.
ENV LIBVA_DRIVER_NAME=bc250
ENV BC250_SHADER_DIR=/usr/share/bc250/shaders
ENV BC250_FAST_MODE=1
ENV BC250_SLICES_PER_FRAME=2
ENV BC250_H264_BACKEND=x264
ENV OMP_WAIT_POLICY=PASSIVE
ENV GOMP_SPINCOUNT=0
ENV OMP_NUM_THREADS=2

# No USER directive here — inherit the base (root). The base entrypoint
# creates the retro user and drops to it at runtime. Do not add USER retro.
# Inherit ENTRYPOINT/CMD from base — gamescope + Steam + WiVRn startup
