#!/usr/bin/env bash
# One-time Steam setup via a real GUI — VNC / browser, no CLI hacks.
#
# The headless CLI path (steam -login, VDF edits, steam:// URLs) fights
# Steam's GUI-first design and fails silently. This runs the SAME image +
# SAME named volumes with a custom command that starts Xvnc + openbox +
# Steam, instead of wivrn-session.sh. You get a real Steam window.
#
# Usage: ./setup-vnc.sh
#   1. Make sure the WiVRn container is NOT running (setup uses the same volumes):
#      sudo podman rm -f wivrn-alyx  (or ./stop-setup-vnc.sh if setup is running)
#   2. ./setup-vnc.sh
#   3. Browser -> http://<CoreOS-IP>:6080/vnc.html -> click Connect
#      (or VNC client -> <CoreOS-IP>:5900, no password)
#   4. In Steam: log in, install Alyx, set Proton + Launch Options (see on-screen)
#   5. Close Steam, then: ./stop-setup-vnc.sh
#   6. ./run.sh  (WiVRn play container), connect Quest, ./launch-alyx.sh
#
# Security: VNC has NO password and is LAN-only. Do NOT expose 5900/6080
# to the internet. Stop the setup container when done.
set -euo pipefail

# Volumes (same as run.sh — Steam data is shared)
sudo podman volume exists wivrn-alyx-steam || sudo podman volume create wivrn-alyx-steam
sudo podman volume exists wivrn-alyx-wivrn || sudo podman volume create wivrn-alyx-wivrn

# Stop any running play container first — both use the same volumes.
if sudo podman ps --filter name=wivrn-alyx --format '{{.Names}}' | grep -q .; then
  echo "Stopping play container wivrn-alyx (setup uses the same volumes)..."
  sudo podman rm -f wivrn-alyx
fi
sudo podman rm -f wivrn-alyx-setup 2>/dev/null || true

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
echo "Starting VNC setup container..."
echo "  Browser -> http://${HOST_IP:-<CoreOS-IP>}:6080/vnc.html -> click Connect"
echo "  VNC client -> ${HOST_IP:-<CoreOS-IP>}:5900 (no password)"
echo "  Logs: sudo podman logs -f wivrn-alyx-setup"
echo "  Stop: ./stop-setup-vnc.sh"
echo ""

exec sudo podman run --rm -it \
  --name wivrn-alyx-setup \
  -p 5900:5900 \
  -p 6080:6080 \
  --ipc host \
  --device /dev/dri:/dev/dri \
  --device /dev/input:/dev/input \
  --device /dev/uinput:/dev/uinput \
  --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --device-cgroup-rule 'c 13:* rwm' \
  --device-cgroup-rule 'c 244:* rwm' \
  -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
  -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
  -e LIBVA_DRIVER_NAME=bc250 \
  -e BC250_FAST_MODE=1 \
  -e BC250_SLICES_PER_FRAME=2 \
  -e BC250_H264_BACKEND=${BC250_H264_BACKEND:-x264} \
  wivrn-alyx:bc250 /opt/setup-vnc/start-vnc.sh
