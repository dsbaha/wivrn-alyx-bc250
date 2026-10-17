#!/usr/bin/env bash
# Find where Alyx actually is — checks BOTH Steam roots + all volumes.
# Fedora Steam can install to either:
#   ~/.local/share/Steam/steamapps/
#   ~/.steam/debian-installation/steamapps/
#   ~/.steam/steam/steamapps/  (symlink, usually -> debian-installation or .local/share)
# The wizard used to check only the first root, so it said "not installed"
# when Alyx was fully installed in the other root.
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"
# If the play container isn't running, check the setup container, else any container.
for C in "$CONTAINER" wivrn-alyx-setup; do
  if sudo podman ps --filter name="$C" --format '{{.Names}}' | grep -q .; then
    CONTAINER="$C"
    break
  fi
done

echo "Checking container: $CONTAINER"
echo ""

echo "=== appmanifest_546560.acf (any Steam root) ==="
sudo podman exec "$CONTAINER" bash -c '
  for root in ~/.local/share/Steam ~/.steam/debian-installation ~/.steam/steam; do
    m="$root/steamapps/appmanifest_546560.acf"
    if [ -f "$m" ]; then
      echo "FOUND: $m"
      grep -E "StateFlags|BytesDownloaded|BytesToDownload|installdir" "$m" | head -n 5
      echo ""
    else
      echo "not in: $root"
    fi
  done
  echo "--- find (slow, definitive) ---"
  find ~ -name "appmanifest_546560.acf" 2>/dev/null | head -n 5 || echo "find: none"
'

echo ""
echo "=== Alyx game dir (any Steam root) ==="
sudo podman exec "$CONTAINER" bash -c '
  for root in ~/.local/share/Steam ~/.steam/debian-installation ~/.steam/steam; do
    d="$root/steamapps/common/Half-Life Alyx"
    if [ -d "$d" ]; then echo "FOUND: $d ($(du -sh "$d" 2>/dev/null | cut -f1))"; fi
  done
  find ~ -maxdepth 5 -type d -name "Half-Life Alyx" 2>/dev/null | head -n 5 || true
'

echo ""
echo "=== Volumes (host side — where did it actually land?) ==="
sudo podman volume ls --format '{{.Name}}' | grep -i wivrn || echo "no wivrn volumes"
echo "(If you have an OLD volume like wivrn-data / steam-data from an early"
echo " version, Alyx may be in there, not in wivrn-alyx-steam. Check:"
echo "  sudo podman volume inspect <name>  — look at Mountpoint, then ls that dir)"
