#!/bin/bash
# VNC setup desktop — runs INSIDE the container as retro (via entrypoint gosu).
# Started by setup-vnc.sh with a custom command, so it bypasses
# wivrn-session.sh (no WiVRn, no gamescope). Gives you a real Steam GUI.
#
# Xvnc is both the X server AND the VNC server — no separate Xvfb + x11vnc.
#   VNC client -> <host>:5900 (no password, LAN only, setup only)
#   Browser   -> http://<host>:6080/vnc.html (noVNC via websockify)
# Do Steam login, install Alyx, set Proton + Launch Options, then stop.
set -euo pipefail

export DISPLAY=":0"
export HOME="${HOME:-/home/retro}"
mkdir -p /tmp/.X11-unix "$HOME/.vnc"

echo "Starting Xvnc on :0 (1920x1080, no password, LAN only)..."
# -SecurityTypes None + -ac: no VNC password. This is for one-time LAN
# setup only — do NOT expose 5900/6080 to the internet.
Xvnc :0 -geometry 1920x1080 -depth 24 \
  -SecurityTypes None -AlwaysShared -ac \
  -rfbport 5900 \
  >/tmp/xvnc.log 2>&1 &
XVNC_PID=$!
sleep 2

echo "Starting openbox window manager..."
openbox >/tmp/openbox.log 2>&1 &

echo "Starting noVNC (browser -> http://<host>:6080/vnc.html)..."
# novnc web files are at /usr/share/novnc on Fedora
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &

echo ""
echo "VNC ready."
echo "  VNC client -> <CoreOS-IP>:5900 (no password)"
echo "  Browser    -> http://<CoreOS-IP>:6080/vnc.html -> click Connect"
echo ""
echo "In the Steam GUI:"
echo "  1. Log in (type password + email Steam Guard code — you can SEE it now)"
echo "  2. Library -> Half-Life: Alyx -> Install, wait for download"
echo "  3. Right-click Alyx -> Properties -> Compatibility -> Force GE-Proton 9-27"
echo "  4. Properties -> General -> Launch Options: VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%"
echo "  5. Close Steam, then stop this container from the host: ./stop-setup-vnc.sh"
echo ""
echo "Starting Steam GUI..."
# Steam GUI — runs in foreground-ish, but we wait on Xvnc so Ctrl-C / stop
# kills the whole container cleanly.
steam >/tmp/steam-gui.log 2>&1 &

# Wait on Xvnc — container stays up until you stop it from the host.
wait "$XVNC_PID"
