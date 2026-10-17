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
#   Container can be wivrn-alyx or wivrn-alyx-setup — same volume.
#   Steam must be CLOSED or it will overwrite on exit (same as VDF edits).
set -euo pipefail

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

sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro bash -c '
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
    echo "No video.txt yet — creating minimal Low one at $VT"
    cat > "$VT" <<EOF
"VideoConfig"
{
  "setting.cpu_level" "0"
  "setting.gpu_level" "0"
  "setting.gpu_mem_level" "0"
  "setting.mat_antialias" "0"
  "setting.mat_forceaniso" "0"
  "setting.mat_vsync" "0"
  "setting.fidelity" "0"
  "setting.shadow_quality" "0"
}
EOF
  fi

  echo ""
  echo "--- setting Low keys (0) where present ---"
  # Only touch keys that exist — do not invent new keys in an existing file.
  # Python is safer than sed for quoted VDF keys.
  python3 - "$VT" <<PYEOF
import re, sys
p = sys.argv[1]
text = open(p).read()
low_keys = {
  "setting.fidelity": "0",
  "setting.gpu_level": "0",
  "setting.gpu_mem_level": "0",
  "setting.cpu_level": "0",
  "setting.shadow_quality": "0",
  "setting.mat_antialias": "0",
  "setting.mat_forceaniso": "0",
  "setting.mat_vsync": "0",
}
for k, v in low_keys.items():
    # Match: "key"  "oldvalue"  ->  "key"  "0"
    pat = re.compile(r"(\"" + re.escape(k) + r"\"\s*\")[^\"]*(\")")
    if pat.search(text):
        text = pat.sub(r"\\1" + v + r"\\2", text)
        print(f"  set {k} -> {v}")
    else:
        print(f"  (not present, skipped) {k}")
open(p, "w").write(text)
PYEOF

  echo ""
  echo "--- after ---"
  cat "$VT"
  echo ""
  echo "Also writing autoexec.cfg (Low cvars, harmless if a cvar does not exist):"
  cat > "$GAME_CFG/autoexec.cfg" <<EOF
// Alyx Low — set by set-alyx-low.sh (BC-250, GPU hang workaround)
// Fidelity 0=Low. If a cvar does not exist in this build, Source ignores it.
vr_fidelity_level 0
r_shadow_quality 0
mat_antialias 0
mat_forceaniso 0
mat_vsync 0
EOF
  cat "$GAME_CFG/autoexec.cfg"
'
echo ""
echo "Done. Now restart the container and launch Alyx — it should start on Low."
echo "If video.txt was missing, the game will create it on first menu open;"
echo "re-run ./set-alyx-low.sh after that first launch to force Low."
