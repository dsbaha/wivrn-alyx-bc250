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
if ! sudo podman exec "$CONTAINER" test -f ~/.local/share/Steam/steamapps/appmanifest_546560.acf; then
  echo "ERROR: Alyx NOT installed. Install first:"
  echo "  ./install-alyx.sh"
  echo "  ./setup-steam.sh"
  exit 1
fi
echo "Alyx installed."

echo "Launching Alyx via Steam (steam://launch/546560/VR)..."
# Steam is already running in gamescope in this container. Sending the
# steam:// URL to that instance triggers the launch with the per-game
# LaunchOptions from setup-steam.sh (VR_OVERRIDE + GE-Proton 9-27).
sudo podman exec "$CONTAINER" bash -c 'steam "steam://launch/546560/VR" >/tmp/alyx-launch.log 2>&1 & echo "launch command sent, pid $!"'

echo ""
echo "Watch the launch:"
echo "  sudo podman logs -f $CONTAINER | grep -iE 'alyx|vr_override|wivrn|gamescope|error' "
echo "In the headset you should see Alyx loading within ~30s."
echo "If it falls back to desktop (no HMD image), check setup-steam.sh ran"
echo "and LaunchOptions = VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%"
