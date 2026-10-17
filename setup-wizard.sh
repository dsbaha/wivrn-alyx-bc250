#!/usr/bin/env bash
# Guided setup for Alyx in Podman + WiVRn on BC-250.
# One command, walks you through every step, picks up where you left off.
#
#   ./setup-wizard.sh
#
# Steps:
#   1. Preflight (podman, image, volumes, bc250 driver)
#   2. VNC setup (Steam login + Alyx install, visually — no CLI hacks)
#   3. Wait for Alyx download (polls manifest, shows progress)
#   4. Proton + Launch Options (auto-set, no GUI clicking needed)
#   5. Stop VNC, start WiVRn play container
#   6. Quest connect (Manual IP + 9757 if mDNS doesn't show)
#   7. Launch Alyx
#
# Resume-aware: if VNC is already running and Alyx is already downloading
# (your current state), it skips straight to step 3. Run it again any time.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo ""; echo -e "${BLUE}=== Step $1: $2 ===${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YELLOW}! $1${NC}"; }
err()   { echo -e "${RED}✗ $1${NC}"; }
pause() { echo ""; read -rp "Press Enter to continue... " _; }
ask_yes() { # ask_yes "question" -> returns 0 if yes
  local ans
  read -rp "$1 [y/N] " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

CONTAINER="wivrn-alyx"
SETUP_CONTAINER="wivrn-alyx-setup"
STEAM_HOME="/home/retro/.local/share/Steam"
# Fedora Steam can use either root — check BOTH, not just STEAM_HOME.
STEAM_ROOTS="/home/retro/.local/share/Steam /home/retro/.steam/debian-installation /home/retro/.steam/steam"
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST_IP="${HOST_IP:-<CoreOS-IP>}"

# Find Alyx manifest in ANY Steam root OR any library folder in libraryfolders.vdf.
# Steam can install to a secondary library folder, not just the default steamapps/.
# Fallback: broad find for appmanifest_546560.acf under /home/retro.
find_alyx_manifest() {
  local c="$1" root m lib
  for root in $STEAM_ROOTS; do
    m="$root/steamapps/appmanifest_546560.acf"
    if sudo podman exec "$c" test -f "$m" 2>/dev/null; then
      echo "$m"
      return 0
    fi
    # Secondary libraries from libraryfolders.vdf — paths are quoted "path" "…"
    for lib in $(sudo podman exec "$c" bash -c "grep -oE '\"path\"[[:space:]]*\"[^\"]+\"' $root/steamapps/libraryfolders.vdf 2>/dev/null | sed -E 's/.*\"([^\"]+)\"$/\1/'" 2>/dev/null || true); do
      m="$lib/steamapps/appmanifest_546560.acf"
      if sudo podman exec "$c" test -f "$m" 2>/dev/null; then
        echo "$m"
        return 0
      fi
    done
  done
  # Broad fallback: find anywhere under /home/retro (slow but definitive)
  m="$(sudo podman exec "$c" bash -c 'find /home/retro -name "appmanifest_546560.acf" 2>/dev/null | head -n 1' 2>/dev/null || true)"
  if [[ -n "$m" ]]; then
    echo "$m"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------- Step 1
step 1 "Preflight — podman, image, volumes, BC-250 driver"

command -v podman >/dev/null || { err "podman not found"; exit 1; }
ok "podman found"

sudo podman volume exists wivrn-alyx-steam || sudo podman volume create wivrn-alyx-steam
sudo podman volume exists wivrn-alyx-wivrn || sudo podman volume create wivrn-alyx-wivrn
ok "named volumes ready (wivrn-alyx-steam, wivrn-alyx-wivrn)"

if ! sudo podman images wivrn-alyx:bc250 --format '{{.Repository}}' | grep -q wivrn-alyx; then
  warn "Image wivrn-alyx:bc250 not found — building now (takes a few minutes)..."
  podman build -f Containerfile -t wivrn-alyx:bc250 .
else
  ok "image wivrn-alyx:bc250 exists"
fi

echo "Checking BC-250 driver (vainfo)..."
echo "vainfo reports the driver as 'AMD BC-250 RDNA2' (case varies) — grep -i for that string."
if sudo podman run --rm --device /dev/dri:/dev/dri -e LIBVA_DRIVER_NAME=bc250 \
    wivrn-alyx:bc250 vainfo --display drm --device /dev/dri/renderD128 2>&1 | grep -qi "AMD BC-250 RDNA2"; then
  ok "bc250 VA-API driver loads (vainfo shows AMD BC-250 RDNA2)"
else
  err "vainfo does NOT show 'AMD BC-250 RDNA2' — WiVRn would fall back to software. Stop here."
  echo "Check: /dev/dri/renderD128 exists, LIBVA_DRIVER_NAME=bc250"
  echo "Run manually to see full vainfo output:"
  echo "  sudo podman run --rm --device /dev/dri:/dev/dri -e LIBVA_DRIVER_NAME=bc250 wivrn-alyx:bc250 vainfo --display drm --device /dev/dri/renderD128"
  exit 1
fi

# ------------------------------------------------- Step 2: VNC (resume-aware)
step 2 "VNC setup — Steam login + Alyx install (visual GUI)"

if sudo podman ps --filter name="$SETUP_CONTAINER" --format '{{.Names}}' | grep -q .; then
  ok "VNC setup container is ALREADY running — resuming (not restarting it)"
else
  if sudo podman ps --filter name="$CONTAINER" --format '{{.Names}}' | grep -q .; then
    echo "Stopping play container (setup uses the same volumes)..."
    sudo podman rm -f "$CONTAINER"
  fi
  echo "Starting VNC setup container..."
  echo ""
  echo -e "  Browser -> ${GREEN}http://${HOST_IP}:6080/vnc.html${NC} -> click Connect"
  echo -e "  VNC client -> ${GREEN}${HOST_IP}:5900${NC} (no password, LAN only)"
  echo ""
  # Start VNC in background via setup-vnc.sh logic (it execs, so run detached here)
  sudo podman run -d --rm --name "$SETUP_CONTAINER" \
    -p 5900:5900 -p 6080:6080 \
    --ipc host \
    --device /dev/dri:/dev/dri \
    --device /dev/input:/dev/input \
    --device /dev/uinput:/dev/uinput \
    --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
    --security-opt seccomp=unconfined --security-opt label=disable \
    --device-cgroup-rule 'c 13:* rwm' --device-cgroup-rule 'c 244:* rwm' \
    -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
    -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
    -e LIBVA_DRIVER_NAME=bc250 -e BC250_FAST_MODE=1 \
    -e BC250_SLICES_PER_FRAME=2 -e BC250_H264_BACKEND=${BC250_H264_BACKEND:-x264} \
    wivrn-alyx:bc250 /opt/setup-vnc/start-vnc.sh >/dev/null
  ok "VNC setup container started"
fi

echo ""
echo "In the VNC window (browser or VNC client):"
echo "  1. Log into Steam (password + email Steam Guard code — you can SEE it now)"
echo "  2. Library -> Half-Life: Alyx -> Install"
echo "  3. Leave the download running — this wizard will watch it."
echo ""
echo "If you already logged in and Alyx is already downloading, just continue."
pause

# ------------------------------------------- Step 3: wait for Alyx download
step 3 "Waiting for Alyx download (~67 GB)"

echo "Polling for Alyx manifest + download progress (Ctrl-C to stop — download keeps running)..."
echo "Checks default steamapps + libraryfolders.vdf secondary libraries + broad find."
echo "If Steam shows Alyx as installed but no manifest is found, run ./find-alyx.sh —"
echo "it checks libraryfolders.vdf + every Podman volume (incl. old wivrn-data)."
while true; do
  MANIFEST="$(find_alyx_manifest "$SETUP_CONTAINER" || true)"
  if [[ -n "$MANIFEST" ]]; then
    # Read StateFlags + Bytes from the manifest (best-effort, VDF is text)
    INFO="$(sudo podman exec "$SETUP_CONTAINER" bash -c "grep -E 'StateFlags|BytesDownloaded|BytesToDownload|\"name\"' '$MANIFEST' 2>/dev/null | tr -d '\t\"' | tr '\n' ' ' " || true)"
    echo "  manifest: $MANIFEST"
    echo "  $INFO"
    if sudo podman exec "$SETUP_CONTAINER" bash -c "grep -q '\"StateFlags\"[[:space:]]*\"4\"' '$MANIFEST'" 2>/dev/null; then
      ok "Alyx download COMPLETE (StateFlags 4) in $MANIFEST"
      break
    fi
    echo "  ... still downloading (or installing). Checking again in 30s."
  else
    echo "  ... no Alyx manifest yet in either Steam root — is Alyx installing in VNC?"
    echo "      If not, go to Library -> Half-Life: Alyx -> Install in VNC, then come back."
    echo "      If Steam shows Alyx as installed but no manifest is found, run ./find-alyx.sh"
  fi
  sleep 30
done

# ------------------------------ Step 4: Proton + Launch Options (auto-set)
step 4 "Proton + Launch Options (auto-set, no GUI clicking)"

echo "Steam must be CLOSED for VDF edits (Steam overwrites on exit)."
echo "In the VNC window: Steam -> Exit (or close the Steam window), then come back here."
pause

echo "Applying Proton + Launch Options via setup-steam.sh logic..."
# Reuse the existing setup-steam.sh, but point it at the SETUP container
# (same volumes, Steam is closed there). CONTAINER env overrides the default.
CONTAINER="$SETUP_CONTAINER" ./setup-steam.sh || {
  err "setup-steam.sh failed — check that Steam was fully closed in VNC and try again."
  echo "Fallback: set them manually in VNC (right-click Alyx -> Properties):"
  echo "  Compatibility -> Force GE-Proton 9-27"
  echo "  Launch Options: VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%"
  exit 1
}
ok "Proton GE-Proton 9-27 + VR_OVERRIDE LaunchOptions set"

# Also ensure GE-Proton 9-27 is actually installed (Steam only lists what it has).
# If the compat tool dir is missing, warn — Steam will download it on first launch.
if sudo podman exec "$SETUP_CONTAINER" bash -c "ls -d $STEAM_HOME/compatibilitytools.d/GE-Proton9-27 $STEAM_HOME/compatibilitytools.d/GE-Proton9-27/* 2>/dev/null | head -n 1" | grep -q GE-Proton; then
  ok "GE-Proton 9-27 found in compatibilitytools.d"
else
  warn "GE-Proton 9-27 NOT found in compatibilitytools.d yet."
  echo "Steam will download it on first Alyx launch. If Alyx falls back to another"
  echo "Proton, install GE-Proton 9-27 in VNC via ProtonUp-Qt or Steam's Compatibility menu."
fi

# --------------------------------- Step 5: stop VNC, start WiVRn container
step 5 "Stop VNC, start WiVRn play container"

echo "Stopping VNC setup container..."
sudo podman rm -f "$SETUP_CONTAINER" 2>/dev/null || true
ok "VNC stopped"

echo "Starting WiVRn play container (./run.sh) in the background..."
# run.sh execs with -it + --rm, so start the same container detached for the wizard.
sudo podman run -d --rm --name "$CONTAINER" \
  --network host --ipc host \
  --device /dev/dri:/dev/dri --device /dev/input:/dev/input --device /dev/uinput:/dev/uinput \
  --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
  --security-opt seccomp=unconfined --security-opt label=disable \
  --device-cgroup-rule 'c 13:* rwm' --device-cgroup-rule 'c 244:* rwm' \
  -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
  -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
  -e GAMESCOPE_BACKEND=headless \
  -e LIBVA_DRIVER_NAME=bc250 -e BC250_FAST_MODE=1 \
  -e BC250_SLICES_PER_FRAME=2 -e BC250_H264_BACKEND=${BC250_H264_BACKEND:-x264} \
  -e OMP_WAIT_POLICY=PASSIVE -e GOMP_SPINCOUNT=0 \
  wivrn-alyx:bc250 >/dev/null
ok "WiVRn container started"

echo "Waiting for wivrn-server on 9757..."
for _ in $(seq 1 30); do
  if sudo ss -lnt 2>/dev/null | grep -q 9757; then ok "wivrn-server listening on 9757"; break; fi
  sleep 2
done

# ---------------------------------------------------- Step 6: Quest connect
step 6 "Connect the Quest 3"

echo "On the Quest 3, open the WiVRn app:"
echo "  - Disable hand tracking, wake the physical controllers BEFORE connecting."
echo "  - If the server shows via mDNS, tap it."
echo "  - If NOT (mDNS is flaky here), use Manual / Add server:"
echo -e "      IP: ${GREEN}${HOST_IP}${NC}   Port: ${GREEN}9757${NC}"
echo ""
echo "PAIRING PIN — first-time Quest connect needs this:"
echo "WiVRn prints 'To pair a new headset use PIN code: XXXX' to the server"
echo "logs + a desktop notification you never see headless. The wizard"
echo "surfaces it here so you don't have to dig through podman logs."
echo "Watching logs for the PIN (takes a few seconds after the headset tries to connect)..."
# Poll logs for the PIN for up to 60s, print it big when found.
PIN=""
for _ in $(seq 1 30); do
  PIN="$(sudo podman logs --tail 200 "$CONTAINER" 2>&1 | grep -oE 'To pair a new headset use PIN code: [0-9]+' | tail -n 1 | grep -oE '[0-9]+$' || true)"
  if [[ -n "$PIN" ]]; then break; fi
  sleep 2
done
if [[ -n "$PIN" ]]; then
  echo ""
  echo -e "  ${GREEN}>>> WiVRn pairing PIN: ${PIN} <<<${NC}"
  echo "  Enter this PIN on the Quest when it asks to pair."
  echo ""
else
  echo "  (No PIN in logs yet — it appears when the headset first tries to pair."
  echo "   If the Quest asks for a PIN, get it with: sudo podman logs $CONTAINER | grep 'PIN code')"
fi
echo ""
echo "Wait until the headset says 'waiting for an application to start', then come back here."
pause

# ------------------------------------------------------ Step 7: Launch Alyx
step 7 "Launch Alyx"

echo "Launching Alyx via Steam (steam://launch/546560/VR)..."
./launch-alyx.sh

echo ""
echo -e "${GREEN}Done — Alyx should be loading in the headset within ~30s.${NC}"
echo ""
echo "If it falls back to desktop (no HMD image):"
echo "  ./check-apps.sh   (checks manifest, Proton, LaunchOptions, logs)"
echo "If the server stops showing on the LAN:"
echo "  ./check-network.sh  (or just use Manual IP + 9757 in the Quest app)"
echo ""
echo "To play again later: ./run.sh, connect Quest, ./launch-alyx.sh"
echo "To re-do setup: ./setup-vnc.sh (VNC GUI) or ./setup-wizard.sh (this wizard)"
