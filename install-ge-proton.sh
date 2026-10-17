#!/usr/bin/env bash
# Install GE-Proton 9-27 into the Steam volume.
# GE-Proton is NOT in Steam's built-in Compatibility list — it's a community
# build from GloriousEggroll. Steam only lists Proton versions it has already
# downloaded, so if you never installed GE-Proton, the dropdown won't show it
# and the wizard's CompatToolMapping to GE-Proton9-27 points at nothing.
#
# This downloads the official GE-Proton9-27.tar.gz from GitHub and extracts
# it to ~/.local/share/Steam/compatibilitytools.d/GE-Proton9-27/ as retro.
# Alyx needs GE-Proton 9-27 specifically: Proton 10 crashes Alyx, native exits.
#
# Usage: ./install-ge-proton.sh [GE-Proton9-27]
#   Container can be wivrn-alyx (play) or wivrn-alyx-setup (VNC) — either works,
#   same volume. If no container is running, uses a one-shot container.
set -euo pipefail

VERSION="${1:-GE-Proton9-27}"
CONTAINER=""
for C in wivrn-alyx-setup wivrn-alyx; do
  if sudo podman ps --filter name="$C" --format '{{.Names}}' | grep -q .; then
    CONTAINER="$C"
    break
  fi
done

URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${VERSION}/${VERSION}.tar.gz"
echo "Installing ${VERSION} from:"
echo "  ${URL}"
echo ""

if [[ -n "$CONTAINER" ]]; then
  echo "Using running container: $CONTAINER (as retro)"
  sudo podman exec "$CONTAINER" gosu retro env HOME=/home/retro bash -c "
    set -e
    mkdir -p /home/retro/.local/share/Steam/compatibilitytools.d
    cd /tmp
    echo 'Downloading ${VERSION}.tar.gz (~400 MB)...'
    curl -L -o ${VERSION}.tar.gz '${URL}'
    echo 'Extracting to compatibilitytools.d/...'
    tar -xzf ${VERSION}.tar.gz -C /home/retro/.local/share/Steam/compatibilitytools.d/
    rm -f ${VERSION}.tar.gz
    ls -l /home/retro/.local/share/Steam/compatibilitytools.d/${VERSION}/proton
    echo 'Done.'
  "
else
  echo "No container running — using one-shot container with the Steam volume."
  sudo podman run --rm \
    -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
    wivrn-alyx:bc250 gosu retro env HOME=/home/retro bash -c "
      set -e
      mkdir -p /home/retro/.local/share/Steam/compatibilitytools.d
      cd /tmp
      echo 'Downloading ${VERSION}.tar.gz (~400 MB)...'
      curl -L -o ${VERSION}.tar.gz '${URL}'
      echo 'Extracting to compatibilitytools.d/...'
      tar -xzf ${VERSION}.tar.gz -C /home/retro/.local/share/Steam/compatibilitytools.d/
      rm -f ${VERSION}.tar.gz
      ls -l /home/retro/.local/share/Steam/compatibilitytools.d/${VERSION}/proton
      echo 'Done.'
    "
fi

echo ""
echo "GE-Proton ${VERSION} installed. Now re-run:"
echo "  ./setup-steam.sh   (sets CompatToolMapping to ${VERSION}, if not already)"
echo "  ./launch-alyx.sh"
