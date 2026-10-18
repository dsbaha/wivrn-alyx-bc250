#!/usr/bin/env bash
# Set Alyx graphics to Low via config file (no GUI clicking).
# Alyx is Source 2 — video settings live in video.txt, either in:
#   <game>/game/hlvr/cfg/video.txt
#   <Steam>/userdata/<id>/546560/remote/cfg/video.txt  (Steam Cloud copy)
# The key that matters is "setting.fidelity" (0=Low, 1=Medium, 2=High, 3=Ultra).
# This script finds video.txt wherever it is, backs it up, sets fidelity +
# shadow / AA / texture keys to Low (0), and prints the result so you can
# see the actual keys on your install. If no video.txt exists yet (game
# never launched to main menu), it creates a minimal Low one.
#
# Usage: ./set-alyx-low.sh
#   FIDELITY=1 ./set-alyx-low.sh  — set Medium (1) instead of Low (0).
#   Container can be wivrn-alyx or wivrn-alyx-setup — same volume.
#   Steam must be CLOSED or it will overwrite on exit (same as VDF edits).
set -euo pipefail

# Fidelity level to write: 0=Low, 1=Medium, 2=High, 3=Ultra.
# Default 0 (Low) — the crash-safe setting on BC-250.
FIDELITY="${FIDELITY:-0}"
case "$FIDELITY" in
  0) FIDELITY_NAME="Low" ;;
  1) FIDELITY_NAME="Medium" ;;
  2) FIDELITY_NAME="High" ;;
  3) FIDELITY_NAME="Ultra" ;;
  *) echo "ERROR: FIDELITY must be 0-3, got '$FIDELITY'" >&2; exit 1 ;;
esac
echo "Target fidelity: $FIDELITY_NAME ($FIDELITY)"

CONTAINER=""
for C in wivrn-alyx-setup wivrn-alyx; do
  if sudo podman ps --filter name="$C" --format '{{.Names}}' | grep -q .; then
    CONTAINER="$C"
    break
  fi
done
if [[ -z "$CONTAINER" ]]; then
  echo "No container running — start one first (./run.sh or ./setup-vnc.sh), then re-run."
  exit 1
fi

echo "Using container: $CONTAINER"
echo "Steam must be CLOSED in the container or it will overwrite on exit."
echo ""

sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro FIDELITY="$FIDELITY" FIDELITY_NAME="$FIDELITY_NAME" bash -c '
  set -e
  GAME_CFG="/home/retro/.local/share/Steam/steamapps/common/Half-Life Alyx/game/hlvr/cfg"
  echo "=== game cfg dir ==="
  ls -l "$GAME_CFG" 2>&1 | head -n 30 || echo "(no game cfg dir yet)"
  echo ""
  echo "=== video.txt locations ==="
  find /home/retro/.local/share/Steam -name "video.txt" -path "*546560*" 2>/dev/null | head -n 10
  find /home/retro/.local/share/Steam/steamapps/common/"Half-Life Alyx" -name "video.txt" 2>/dev/null | head -n 10
  echo ""

  # Pick the game-dir video.txt as canonical (Steam Cloud will sync from it).
  mkdir -p "$GAME_CFG"
  VT="$GAME_CFG/video.txt"
  if [ -f "$VT" ]; then
    cp "$VT" "$VT.bak"
    echo "Backed up $VT -> $VT.bak"
    echo "--- before ---"
    cat "$VT"
  else
    echo "No video.txt yet — creating minimal $FIDELITY_NAME one at $VT"
    cat > "$VT" <<EOF
"VideoConfig"
{
  "setting.cpu_level" "$FIDELITY"
  "setting.gpu_level" "$FIDELITY"
  "setting.gpu_mem_level" "$FIDELITY"
  "setting.mat_antialias" "$FIDELITY"
  "setting.mat_forceaniso" "$FIDELITY"
  "setting.mat_vsync" "0"
  "setting.fidelity" "$FIDELITY"
  "setting.shadow_quality" "$FIDELITY"
}
EOF
  fi

  echo ""
  echo "--- setting $FIDELITY_NAME keys ($FIDELITY) where present ---"
  # Only touch keys that exist — do not invent new keys in an existing file.
  # Python is safer than sed for quoted VDF keys.
  python3 - "$VT" <<PYEOF
import os, re, sys
p = sys.argv[1]
fid = os.environ.get("FIDELITY", "0")
text = open(p).read()
low_keys = {
  "setting.fidelity": fid,
  "setting.gpu_level": fid,
  "setting.gpu_mem_level": fid,
  "setting.cpu_level": fid,
  "setting.shadow_quality": fid,
  "setting.mat_antialias": fid,
  "setting.mat_forceaniso": fid,
  "setting.mat_vsync": "0",
}
for k, v in low_keys.items():
    # Match: "key"  "oldvalue"  ->  "key"  "0"
    pat = re.compile(r"(\"" + re.escape(k) + r"\"\s*\")[^\"]*(\")")
    if pat.search(text):
        # Use lambda, NOT r"\1" + v + r"\2": with v="0" that becomes "\10"
        # which re.sub parses as group 10 -> "invalid group reference".
        text = pat.sub(lambda m, v=v: m.group(1) + v + m.group(2), text)
        print(f"  set {k} -> {v}")
    else:
        print(f"  (not present, skipped) {k}")
open(p, "w").write(text)
PYEOF

  echo ""
  echo "--- after ---"
  cat "$VT"
  echo ""
  echo "--- syncing $FIDELITY_NAME to Steam Cloud copies (persistence fix) ---"
  echo "Steam Cloud holds its own video.txt in userdata/*/546560/remote/cfg/."
  echo "If Cloud has a different fidelity, it OVERWRITES the game-dir file on launch,"
  echo "so $FIDELITY_NAME never persists. Copy the $FIDELITY_NAME file to ALL Cloud copies."
  for cloud in /home/retro/.local/share/Steam/userdata/*/546560/remote/cfg/video.txt; do
    if [ -f "$cloud" ]; then
      cp "$cloud" "$cloud.bak"
      cp "$VT" "$cloud"
      echo "  synced $FIDELITY_NAME -> $cloud (backed up to .bak)"
    fi
  done
  for d in /home/retro/.local/share/Steam/userdata/*/546560/remote/cfg/; do
    if [ -d "$d" ] && [ ! -f "$d/video.txt" ]; then
      cp "$VT" "$d/video.txt"
      echo "  created $FIDELITY_NAME Cloud copy -> $d/video.txt"
    fi
  done
  echo "  (Also: in VNC, Alyx -> Properties -> General -> Steam Cloud OFF"
  echo "   prevents Cloud from ever reverting this again.)"
  echo ""
  echo "Also writing autoexec.cfg ($FIDELITY_NAME cvars, harmless if a cvar does not exist):"
  cat > "$GAME_CFG/autoexec.cfg" <<EOF
// Alyx $FIDELITY_NAME — set by set-alyx-low.sh (BC-250)
// Fidelity $FIDELITY (0=Low). If a cvar does not exist in this build, Source ignores it.
vr_fidelity_level $FIDELITY
r_shadow_quality $FIDELITY
mat_antialias $FIDELITY
mat_forceaniso $FIDELITY
mat_vsync 0
EOF
  cat "$GAME_CFG/autoexec.cfg"
'
echo ""
echo "Done. Now restart the container and launch Alyx — it should start on $FIDELITY_NAME."
echo "If video.txt was missing, the game will create it on first menu open;"
echo "re-run ./set-alyx-low.sh after that first launch to force $FIDELITY_NAME."
