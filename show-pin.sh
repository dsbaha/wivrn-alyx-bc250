#!/usr/bin/env bash
# Show the WiVRn pairing PIN — no digging through podman logs.
# WiVRn prints "To pair a new headset use PIN code: XXXX" to server stderr
# + a desktop notification you never see headless. This prints it big.
# Usage: ./show-pin.sh
set -euo pipefail
CONTAINER="${CONTAINER:-wivrn-alyx}"
echo "Watching $CONTAINER logs for the pairing PIN (Ctrl-C to stop)..."
echo "Trigger it by connecting from the Quest — the PIN appears when the headset first tries to pair."
echo ""
# First check existing logs, then follow.
PIN="$(sudo podman logs --tail 500 "$CONTAINER" 2>&1 | grep -oE 'To pair a new headset use PIN code: [0-9]+' | tail -n 1 | grep -oE '[0-9]+$' || true)"
if [[ -n "$PIN" ]]; then
  echo ">>> WiVRn pairing PIN: $PIN <<<"
  echo "Enter this PIN on the Quest when it asks to pair."
  exit 0
fi
echo "(No PIN in logs yet — waiting for the headset to try to pair...)"
sudo podman logs -f "$CONTAINER" 2>&1 | grep --line-buffered -E 'PIN code|Incorrect PIN' | while read -r line; do
  echo ">>> $line <<<"
done
