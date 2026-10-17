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

ARG BC250_VERSION=v0.5.4

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
# + VNC-for-setup: Steam login/install/Proton is GUI-first. Headless CLI
# hacks (steam -login, VDF edits, steam:// URLs) fight Steam's design and
# fail silently with no screen to see. The VNC setup container (same image,
# custom command) gives you a real Steam GUI via browser/VNC for one-time
# setup. See setup-vnc.sh. These packages are only used by the setup path;
# the WiVRn play path does not start VNC.
RUN dnf install -y --setopt=install_weak_deps=False \
      libgomp libva vulkan-loader libdrm \
      libva-utils ffmpeg \
      tigervnc-server openbox novnc python3-websockify \
      xorg-x11-fonts-Type1 \
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

# x264 tuning: GoW's wivrn-config.sh does NOT expose bitrate or x264
# preset/tune/threads — it regenerates config.json on every start, so a
# manual edit gets wiped. Patch it to support:
#   WIVRN_BITRATE (e.g. 20000000 = 20 Mbps, empty = WiVRn default)
#   WIVRN_X264_PRESET (ultrafast, superfast, veryfast, faster, fast, medium)
#   WIVRN_X264_TUNE (zerolatency)
#   WIVRN_X264_THREADS (e.g. 8)
# Bitrate goes to top-level "bitrate". x264 opts go to encoder.options
# (passed to avcodec_open2). Only applied when encoder is x264.
RUN python3 - <<'PY'
import pathlib
cfg = pathlib.Path("/opt/gow/wivrn-config.sh")
text = cfg.read_text()
marker = 'log_info "Wrote WiVRn config to ${CONFIG_FILE}"'
assert marker in text, "wivrn-config.sh no longer contains log_info line — check upstream"
patch = marker + '''

# --- BC-250 / Alyx overlay: x264 tuning + bitrate (appended by Containerfile) ---
/usr/bin/python3 <<'PYEOF'
import json, os
config_file = os.environ.get("CONFIG_FILE", os.path.expanduser("~/.config/wivrn/config.json"))
try:
    with open(config_file) as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}
changed = False
bitrate_raw = os.environ.get("WIVRN_BITRATE", "").strip()
if bitrate_raw:
    try:
        config["bitrate"] = int(bitrate_raw)
        changed = True
    except ValueError:
        print(f"[WARN] wivrn-config: WIVRN_BITRATE must be int, got '{bitrate_raw}'", flush=True)
enc = config.get("encoder", "auto")
enc_name = enc if isinstance(enc, str) else enc.get("encoder", "auto")
if enc_name == "x264":
    opts = {"bf": "0"}
    preset = os.environ.get("WIVRN_X264_PRESET", "").strip()
    tune = os.environ.get("WIVRN_X264_TUNE", "").strip()
    threads = os.environ.get("WIVRN_X264_THREADS", "").strip()
    if preset:
        opts["preset"] = preset
    if tune:
        opts["tune"] = tune
    if threads:
        opts["threads"] = threads
    if isinstance(enc, str):
        new_enc = {"encoder": "x264", "options": opts}
        codec = os.environ.get("WIVRN_CODEC", "").strip().lower()
        if codec:
            new_enc["codec"] = codec
        config["encoder"] = new_enc
    else:
        enc.setdefault("options", {}).update(opts)
        config["encoder"] = enc
    changed = True
    print(f"[INFO] wivrn-config: x264 tuning preset={preset or '(default)'} tune={tune or '(default)'} threads={threads or '(default)'} bitrate={config.get('bitrate', '(default)')}", flush=True)
if changed:
    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\\n")
PYEOF
'''
cfg.write_text(text.replace(marker, patch))
print("Patched wivrn-config.sh: added WIVRN_BITRATE + WIVRN_X264_* post-step")
PY
# BC-250: HiZ hangs gfx ring at Alyx loading screen.
# Override at runtime: RADV_DEBUG=... ./run.sh
ENV RADV_DEBUG=nohiz
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

# VNC setup desktop script — run by setup-vnc.sh as a custom command.
# The base entrypoint runs it as retro via gosu, bypassing wivrn-session.sh.
COPY setup-vnc/start-vnc.sh /opt/setup-vnc/start-vnc.sh
RUN chmod +x /opt/setup-vnc/start-vnc.sh

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
