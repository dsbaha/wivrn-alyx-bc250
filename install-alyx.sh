#!/usr/bin/env bash
# Install Alyx via the Steam client already in the container — NOT steamcmd.
# The GoW image installs the `steam` package from RPM Fusion. It does NOT
# install `steamcmd`, so `steamcmd` is not in PATH. That's expected, not a bug.
# Do NOT install steamcmd to get Alyx: steamcmd defaults to ~/Steam and
# would install to a different Steam root than the Steam client uses
# (/home/retro/.local/share/Steam), so the client + WiVRn would not see it.
#
# Usage: ./install-alyx.sh
#   1. Container must be running (./run.sh)
#   2. Steam must be logged in (see README "Steam Guard" — copy host login
#      files, or `podman exec wivrn-alyx steam -login <user> <pass> <guard>`)
#   3. This triggers Steam to install Alyx and polls for the manifest.
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"

echo "Checking container is running..."
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || true

echo "Checking Steam is logged in..."
if ! sudo podman exec "$CONTAINER" test -f /home/retro/.local/share/Steam/config/loginusers.vdf; then
  echo "WARNING: No loginusers.vdf — Steam may not be logged in yet."
  echo "Log in first, either:"
  echo "  (a) Copy host Steam login files into the volume (see README), or"
  echo "  (b) podman exec -it $CONTAINER steam -login <user> <pass> <GuardCode>"
  echo "Then re-run ./install-alyx.sh"
  # Don't exit — Steam may still be logged in via ssfn* without loginusers.vdf
fi

if sudo podman exec "$CONTAINER" test -f /home/retro/.local/share/Steam/steamapps/appmanifest_546560.acf; then
  echo "Alyx already installed (appmanifest_546560.acf exists). Nothing to do."
  echo "Next: ./setup-steam.sh (if you haven't), then ./launch-alyx.sh"
  exit 0
fi

echo "Triggering Alyx install via Steam client (steam://install/546560)..."
echo "Must run as RETRO (gosu), not root — see launch-alyx.sh for why."
sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro XDG_RUNTIME_DIR=/run/user/1000 bash -c 'steam "steam://install/546560" >/tmp/alyx-install.log 2>&1 & echo "install triggered"'

echo "Polling for appmanifest_546560.acf (Ctrl-C to stop polling — install keeps running)..."
for i in $(seq 1 120); do
  if sudo podman exec "$CONTAINER" test -f /home/retro/.local/share/Steam/steamapps/appmanifest_546560.acf; then
    echo ""
    echo "Alyx manifest appeared — install started / finished."
    sudo podman exec "$CONTAINER" bash -c "grep -E 'StateFlags|BytesDownloaded|BytesToDownload' /home/retro/.local/share/Steam/steamapps/appmanifest_546560.acf 2>/dev/null || true"
    echo "If StateFlags is not 4 (fully installed), wait for the download to finish."
    echo "Next: ./setup-steam.sh, then ./launch-alyx.sh"
    exit 0
  fi
  printf "."
  sleep 5
done
echo ""
echo "Manifest still not there after 10 min. Check Steam is logged in and Alyx is owned:"
echo "  sudo podman logs --tail 50 $CONTAINER"
