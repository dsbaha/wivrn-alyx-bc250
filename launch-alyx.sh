#!/usr/bin/env bash
# Launch Alyx AFTER the Quest has connected to WiVRn (manual or mDNS).
# "Waiting for an application to start" means the headset is connected and
# wivrn-server is up, but no OpenXR app is submitting frames yet.
# WiVRn does NOT auto-start a game unless WIVRN_APPLICATION is set.
# This script tells the Steam instance already running in the container
# (inside gamescope) to launch Alyx in VR.
#
# Usage: ./launch-alyx.sh
#   1. Connect from the Quest (manual IP + 9757, or mDNS if it works)
#   2. Wait until the headset says "waiting for an application to start"
#   3. Run this from another terminal on the CoreOS box
#   4. Alyx should start and appear in the headset within ~30s
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"

echo "Checking container is running..."
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || true

echo "Checking Alyx is installed (appmanifest_546560.acf)..."
if ! sudo podman exec "$CONTAINER" test -f /home/retro/.local/share/Steam/steamapps/appmanifest_546560.acf; then
  echo "ERROR: Alyx NOT installed. Install first:"
  echo "  ./install-alyx.sh"
  echo "  ./setup-steam.sh"
  exit 1
fi
echo "Alyx installed."

echo "Launching Alyx via Steam (steam://launch/546560/VR)..."
echo "Must run as RETRO, not root: podman exec defaults to root (HOME=/root),"
echo "so a bare 'steam steam://...' as root hits Steam's 'cannot run as root user'"
echo "check and never reaches the retro Steam in gamescope. Use gosu retro."
echo "Also: old runs left a ROOT-owned /tmp/alyx-launch.log in sticky /tmp, which"
echo "retro cannot overwrite — remove it first, and log to retro's HOME instead."
sudo podman exec "$CONTAINER" rm -f /tmp/alyx-launch.log
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro XDG_RUNTIME_DIR=/run/user/1000 bash -c 'steam "steam://launch/546560/VR" >/home/retro/alyx-launch.log 2>&1 & echo "launch command sent, pid $!"'
echo "Log inside container: /home/retro/alyx-launch.log (as retro)"
echo "View it: sudo podman exec $CONTAINER cat /home/retro/alyx-launch.log"

echo ""
echo "Watch the launch:"
echo "  sudo podman logs -f $CONTAINER | grep -iE 'alyx|vr_override|wivrn|gamescope|error' "
echo "In the headset you should see Alyx loading within ~30s."
echo "If it falls back to desktop (no HMD image), check setup-steam.sh ran"
echo "and LaunchOptions = VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%"
