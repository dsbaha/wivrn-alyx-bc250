#!/usr/bin/env bash
# Find where Alyx ACTUALLY is — definitive version.
# Previous versions only checked the default steamapps dir in two Steam roots.
# That misses:
#   - Secondary Steam library folders (libraryfolders.vdf) — Alyx can be in
#     any library folder, not just the default steamapps/
#   - Old volumes (wivrn-data, steam-data, etc.) from earlier repo versions
# This script checks ALL of those: libraryfolders.vdf in every Steam root,
# a broad find inside the container, AND every Podman volume on the host.
set -euo pipefail

echo "=== 1. Containers (which one has Steam?) ==="
sudo podman ps -a --filter name=wivrn-alyx --format '{{.Names}} {{.Status}}' || true

echo ""
echo "=== 2. Inside container: libraryfolders.vdf (ALL library folders) ==="
for C in wivrn-alyx-setup wivrn-alyx; do
  if sudo podman ps --filter name="$C" --format '{{.Names}}' | grep -q .; then
    echo "--- container $C ---"
    sudo podman exec "$C" bash -c '
      for root in /home/retro/.local/share/Steam /home/retro/.steam/debian-installation /home/retro/.steam/steam; do
        lf="$root/steamapps/libraryfolders.vdf"
        if [ -f "$lf" ]; then
          echo "libraryfolders.vdf in $root:"
          cat "$lf" | grep -E "\"path\"|\"label\"" | head -n 20
          echo ""
        fi
      done
    ' || true
  fi
done

echo ""
echo "=== 3. Inside container: appmanifest_546560.acf ANYWHERE under /home/retro ==="
for C in wivrn-alyx-setup wivrn-alyx; do
  if sudo podman ps --filter name="$C" --format '{{.Names}}' | grep -q .; then
    echo "--- container $C ---"
    sudo podman exec "$C" bash -c 'find /home/retro -name "appmanifest_546560.acf" 2>/dev/null | head -n 10; echo "(end find)"; find /home/retro -maxdepth 6 -type d -name "Half-Life Alyx" 2>/dev/null | head -n 10; echo "(end dir find)"' || true
  fi
done

echo ""
echo "=== 4. Host volumes: search EVERY wivrn/steam volume mountpoint ==="
for VOL in $(sudo podman volume ls --format '{{.Name}}' | grep -iE 'wivrn|steam|alyx' || true); do
  MP="$(sudo podman volume inspect "$VOL" --format '{{.Mountpoint}}' 2>/dev/null || true)"
  echo "--- volume $VOL -> $MP ---"
  if [[ -n "$MP" && -d "$MP" ]]; then
    sudo find "$MP" -maxdepth 5 -name "appmanifest_546560.acf" 2>/dev/null | head -n 5 || true
    sudo find "$MP" -maxdepth 5 -type d -name "Half-Life Alyx" 2>/dev/null | head -n 5 || true
    echo "  top-level: $(sudo ls "$MP" 2>/dev/null | head -n 10 | tr '\n' ' ')"
  else
    echo "  (no mountpoint or not a dir)"
  fi
done

echo ""
echo "=== 5. All Podman volumes (in case the name doesn't contain wivrn/steam) ==="
sudo podman volume ls --format '{{.Name}}' || true
echo ""
echo "If Alyx is in an OLD volume (e.g. wivrn-data, steam-data) and NOT in"
echo "wivrn-alyx-steam, the fix is to point the play container at that volume"
echo "(or copy the Steam data into wivrn-alyx-steam). Paste this output and"
echo "the wizard can be pointed at the right volume instead of re-downloading."
