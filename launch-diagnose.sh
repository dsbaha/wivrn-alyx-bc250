#!/usr/bin/env bash
# Diagnose "Alyx not launching" — checks every link in the chain.
# Run when: container is up, Quest says "waiting for an application",
# ./launch-alyx.sh says "launch command sent" but nothing appears.
set -euo pipefail
CONTAINER="${CONTAINER:-wivrn-alyx}"
echo "=== container ==="
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || echo "container not running"

echo ""
echo "=== processes (must show wivrn-server + gamescope + steam as retro) ==="
sudo podman exec "$CONTAINER" bash -c 'ps aux | grep -E "wivrn-server|gamescope|steam" | grep -v grep | awk "{print \$1, \$11, \$12, \$13}" | head -n 20 || echo "ps failed"'

echo ""
echo "=== wivrn-server listening on 9757? ==="
sudo podman exec "$CONTAINER" bash -c 'ss -ltn 2>/dev/null | grep 9757 && echo "9757 open" || echo "9757 NOT open"'

echo ""
echo "=== Proton GE-Proton 9-27 installed? ==="
sudo podman exec "$CONTAINER" bash -c 'ls -d /home/retro/.local/share/Steam/compatibilitytools.d/GE-Proton9-27 2>/dev/null && echo "GE-Proton9-27 present" || echo "GE-Proton9-27 MISSING — Steam will try to download it on launch (or fall back)"; ls /home/retro/.local/share/Steam/compatibilitytools.d/ 2>/dev/null | head -n 20 || echo "no compatibilitytools.d"'

echo ""
echo "=== CompatToolMapping for 546560 in config.vdf (must be GE-Proton9-27) ==="
sudo podman exec "$CONTAINER" bash -c 'grep -A 4 "\"546560\"" /home/retro/.local/share/Steam/config/config.vdf 2>/dev/null | head -n 10 || echo "no 546560 in config.vdf — setup-steam.sh did not run or Steam overwrote it"'

echo ""
echo "=== LaunchOptions for 546560 in localconfig.vdf (must contain VR_OVERRIDE) ==="
sudo podman exec "$CONTAINER" bash -c 'for f in /home/retro/.local/share/Steam/userdata/*/config/localconfig.vdf; do echo "--- $f ---"; grep -A 2 "\"546560\"" "$f" 2>/dev/null | head -n 10; done || echo "no localconfig.vdf"'

echo ""
echo "=== Steam login? ==="
sudo podman exec "$CONTAINER" bash -c 'ls -l /home/retro/.local/share/Steam/config/loginusers.vdf /home/retro/.local/share/Steam/ssfn* 2>&1 | head -n 5'

echo ""
echo "=== Recent logs (last 60 lines, filtered) ==="
sudo podman logs --tail 100 "$CONTAINER" 2>&1 | grep -iE 'alyx|vr_override|wivrn|gamescope|error|fail|proton|steam' | tail -n 60 || echo "(no matching log lines)"

echo ""
echo "=== Full recent logs (last 30 lines, unfiltered) ==="
sudo podman logs --tail 30 "$CONTAINER" 2>&1 | tail -n 30
