#!/usr/bin/env bash
# Log into Steam in the container — correctly.
#
# Why `podman exec wivrn-alyx steam -login ...` appears to "ignore" you:
#   1. `podman exec` defaults to root, HOME=/root. The real Steam runs as
#      retro, HOME=/home/retro. Root's `steam -login` talks to /root's
#      Steam (none) and writes to /root, not retro's volume. It looks like
#      nothing happened.
#   2. Steam is already running in gamescope in the container. A second
#      `steam -login` just IPCs to the running instance, which ignores
#      -login if it's already running.
#
# Fix: stop the running container, then run a ONE-SHOT login container that
# runs `steam -login` as retro (via the image entrypoint's gosu) with the
# same named volume, so the ssfn* + token land in wivrn-alyx-steam.
# Then restart the normal container with ./run.sh.
#
# Usage: ./steam-login.sh <steam-username>
#   It will prompt for password + Steam Guard code (email) without echoing.
#   Or: STEAM_USER=... STEAM_PASS=... STEAM_GUARD=... ./steam-login.sh
set -euo pipefail

STEAM_USER="${1:-${STEAM_USER:-}}"
if [[ -z "$STEAM_USER" ]]; then
  read -rp "Steam username: " STEAM_USER
fi
if [[ -z "${STEAM_PASS:-}" ]]; then
  read -rsp "Steam password: " STEAM_PASS
  echo
fi
if [[ -z "${STEAM_GUARD:-}" ]]; then
  echo "If Steam already emailed you a Guard code, enter it now."
  echo "If not, leave blank — Steam will email one, then re-run with the code."
  read -rp "Steam Guard code (email, 5 chars, blank if none yet): " STEAM_GUARD || true
fi

echo "Stopping running container (if any) so login isn't ignored..."
sudo podman rm -f wivrn-alyx 2>/dev/null || true

echo "Running one-shot login as retro (HOME=/home/retro, volume wivrn-alyx-steam)..."
# The image entrypoint runs the given command as retro via gosu when PUID != 0.
# -it is needed so Steam can prompt if the guard code is wrong/expired.
if [[ -n "$STEAM_GUARD" ]]; then
  sudo podman run --rm -it \
    --name wivrn-alyx-login \
    --network host --ipc host \
    --device /dev/dri:/dev/dri \
    --device /dev/input:/dev/input \
    --device /dev/uinput:/dev/uinput \
    --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
    --security-opt seccomp=unconfined --security-opt label=disable \
    -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
    -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
    wivrn-alyx:bc250 steam -login "$STEAM_USER" "$STEAM_PASS" "$STEAM_GUARD"
else
  sudo podman run --rm -it \
    --name wivrn-alyx-login \
    --network host --ipc host \
    --device /dev/dri:/dev/dri \
    --device /dev/input:/dev/input \
    --device /dev/uinput:/dev/uinput \
    --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
    --security-opt seccomp=unconfined --security-opt label=disable \
    -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
    -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
    wivrn-alyx:bc250 steam -login "$STEAM_USER" "$STEAM_PASS"
fi

echo ""
echo "Checking login cached in volume (loginusers.vdf + ssfn*)..."
sudo podman run --rm \
  -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
  wivrn-alyx:bc250 bash -c 'ls -l /home/retro/.local/share/Steam/config/loginusers.vdf /home/retro/.local/share/Steam/ssfn* 2>&1 | head -n 5; echo "---"; grep -o "\"AccountName\"[^,]*" /home/retro/.local/share/Steam/config/loginusers.vdf 2>/dev/null | head -n 2 || echo "loginusers.vdf not readable — login may have failed"'

echo ""
echo "Done. Restart the normal container:"
echo "  ./run.sh"
echo "Then: ./install-alyx.sh  (if Alyx not installed yet)"
