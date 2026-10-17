#!/usr/bin/env bash
# Flat-screen test: launch Alyx WITHOUT VR to see if it hangs the GPU.
# This isolates: if flat ALSO hangs with gfx_0.0.0 timeout / VKRenderThread,
# it's Alyx + RADV on BC-250, not WiVRn / xrizer / OpenXR.
# If flat runs without hanging, it's the VR capture path.
#
# CRITICAL: Must run in the PLAY container (wivrn-alyx), NOT VNC.
# VNC has NO SteamVR and NO WiVRn server running, so Alyx pops up
# "can't find SteamVR" and exits — that's expected in VNC, not a real result.
# Play container HAS WiVRn + xrizer, so Alyx can init OpenVR via xrizer
# even in fake-VR mode. You won't SEE the menu (gamescope headless has no
# visible display), but you CAN tell if it hangs: watch dmesg for gfx
# timeout + check if hlvr stays alive.
#
# How: keep VR_OVERRIDE (so OpenVR -> xrizer -> WiVRn works), append
# "-novr +vr_enable_fake_vr 1" AFTER %command% (Source 2 fake-VR desktop mode).
# LaunchOptions -> "VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command% -novr +vr_enable_fake_vr 1"
# Then restore VR LaunchOptions via ./setup-steam.sh.
#
# Usage:
#   ./launch-alyx-flat.sh
#   # Watch dmesg in another terminal: sudo dmesg -w | grep -iE 'gfx|ring|timeout'
#   # Check hlvr alive: sudo podman exec wivrn-alyx pgrep -a hlvr
#   # When done, stop Alyx, then:
#   ./setup-steam.sh   # restores VR_OVERRIDE LaunchOptions (removes -novr)
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"
STEAM_HOME="/home/retro/.local/share/Steam"

echo "Flat test container: $CONTAINER (must be wivrn-alyx / play, NOT VNC)"
echo "VNC has no SteamVR / WiVRn, so flat test there pops 'can't find SteamVR'."
echo "Checking container is running..."
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || true

echo ""
echo "Backing up current LaunchOptions, then setting flat mode (KEEP VR_OVERRIDE)..."
echo "  LaunchOptions -> VR_OVERRIDE=<detected-xrizer> %command% -novr +vr_enable_fake_vr 1"
echo "  (xrizer path detected inside container — see Python output below)"
# Reuse setup-steam.sh logic but with flat LaunchOptions: edit localconfig.vdf directly.
# KEEP VR_OVERRIDE (so OpenVR -> xrizer works), APPEND -novr + fake VR after %command%.
# Detect xrizer INSIDE the container (Python checks filesystem) — avoids
# passing env through podman exec + gosu env (which drops it).
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro bash -c '
  set -e
  for f in /home/retro/.local/share/Steam/userdata/*/config/localconfig.vdf; do
    echo "Editing $f"
    cp "$f" "$f.bak-flat-test"
    python3 - "$f" <<PYEOF
import os, re, sys
p = sys.argv[1]
text = open(p).read()
# Detect xrizer path that actually exists (same order as setup-steam.sh).
xrizer = ""
for cand in ["/opt/xrizer", "/home/retro/xrizer-hla/xrizer", "/run/host/usr/lib64/xrizer/runtime", "/usr/lib64/xrizer/runtime"]:
    if os.path.exists(cand) or os.path.exists(cand + "/bin/linux64/vrclient.so"):
        xrizer = cand
        break
if xrizer:
    flat = f"VR_OVERRIDE={xrizer} %command% -novr +vr_enable_fake_vr 1"
else:
    flat = "%command% -novr +vr_enable_fake_vr 1"
print(f"  detected xrizer: {xrizer or \"(none, relying on global)\"}")
print(f"  set 546560 LaunchOptions -> {flat}")
# Match: "546560" { ... "LaunchOptions" "old" ... } — replace old value.
pat = re.compile(r"(\"546560\"\s*\{[^}]*?\"LaunchOptions\"\s*\")[^\"]*(\")", re.DOTALL)
if pat.search(text):
    text = pat.sub(lambda m: m.group(1) + flat + m.group(2), text)
    print(f"  set 546560 LaunchOptions -> {flat}")
else:
    print("  (no 546560 LaunchOptions in this file — run ./setup-steam.sh first to create it, then re-run flat test)")
open(p, "w").write(text)
PYEOF
  done
'

echo ""
echo "Launching Alyx flat (no VR, fake VR) in PLAY container..."
echo "You will NOT see the menu (gamescope headless has no visible display)."
echo "Tell-tale is: does it hang the GPU or not?"
echo "  Watch: sudo dmesg -w | grep -iE 'gfx|ring|timeout'"
echo "  Check alive: sudo podman exec wivrn-alyx pgrep -a hlvr"
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro XDG_RUNTIME_DIR=/run/user/1000 bash -c 'steam "steam://launch/546560" >/home/retro/alyx-flat-launch.log 2>&1 & echo "flat launch sent"'

echo ""
echo "If it runs WITHOUT gfx timeout: VR capture path is the problem (WiVRn / xrizer / encode)."
echo "If it ALSO hangs with gfx_0.0.0 timeout / VKRenderThread: Alyx + RADV on BC-250, not VR."
echo ""
echo "When done, stop Alyx in Steam, then restore VR LaunchOptions:"
echo "  ./setup-steam.sh   # removes -novr, back to VR_OVERRIDE %command% only"
