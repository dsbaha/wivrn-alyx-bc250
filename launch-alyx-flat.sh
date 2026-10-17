#!/usr/bin/env bash
# Flat-screen test: launch Alyx WITHOUT VR to see if it renders the main menu.
# This isolates: if flat ALSO hangs with gfx_0.0.0 timeout / VKRenderThread,
# it's Alyx + RADV on BC-250, not WiVRn / xrizer / OpenXR.
# If flat renders the menu fine, it's the VR capture path.
#
# How: temporarily set LaunchOptions to "-novr +vr_enable_fake_vr 1"
# (Source 2 fake-VR desktop mode, no headset needed), launch, watch.
# Then restore VR LaunchOptions via ./setup-steam.sh.
#
# Usage:
#   ./launch-alyx-flat.sh
#   # In VNC (setup container), look for the Alyx window / main menu.
#   # Watch dmesg in another terminal for gfx timeouts.
#   # When done, stop Alyx in Steam, then:
#   ./setup-steam.sh   # restores VR_OVERRIDE LaunchOptions
#
# NOTE: Run this in the VNC setup container (./setup-vnc.sh), NOT the play
# container — VNC shows you the desktop so you can SEE the menu.
# The play container (gamescope headless) has no visible display.
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx-setup}"
STEAM_HOME="/home/retro/.local/share/Steam"

echo "Flat test container: $CONTAINER (should be wivrn-alyx-setup / VNC)"
echo "Checking container is running..."
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || true

echo ""
echo "Backing up current LaunchOptions, then setting flat mode..."
echo "  LaunchOptions -> -novr +vr_enable_fake_vr 1"
# Reuse setup-steam.sh logic but with flat LaunchOptions: edit localconfig.vdf directly.
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro bash -c '
  set -e
  for f in /home/retro/.local/share/Steam/userdata/*/config/localconfig.vdf; do
    echo "Editing $f"
    cp "$f" "$f.bak-flat-test"
    python3 - "$f" <<PYEOF
import re, sys
p = sys.argv[1]
text = open(p).read()
# Replace LaunchOptions for 546560 with flat mode. If no 546560 block, append is skipped — setup-steam.sh handles that case.
flat = "-novr +vr_enable_fake_vr 1"
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
echo "Launching Alyx flat (no VR)..."
echo "In VNC, look for the Alyx window / main menu."
echo "In another terminal, watch: sudo dmesg -w | grep -iE 'gfx|ring|timeout'"
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro XDG_RUNTIME_DIR=/run/user/1000 bash -c 'steam "steam://launch/546560" >/home/retro/alyx-flat-launch.log 2>&1 & echo "flat launch sent"'

echo ""
echo "If menu renders: VR path is the problem (WiVRn / xrizer / capture)."
echo "If it ALSO hangs with gfx_0.0.0 timeout / VKRenderThread: Alyx + RADV on BC-250, not VR."
echo ""
echo "When done, stop Alyx in Steam, then restore VR LaunchOptions:"
echo "  CONTAINER=$CONTAINER ./setup-steam.sh"
