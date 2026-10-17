#!/usr/bin/env bash
# Diagnose "pick an application to start streaming" with an empty list.
# The WiVRn headset picker lists VR apps from Steam's steamapps.vrmanifest.
# If it's empty, one of these is true:
#   1. Alyx isn't installed yet (most common on first run)
#   2. Steam hasn't created the VR manifest yet (Steam hasn't run / finished first-run)
#   3. WiVRn is reading the wrong Steam root (see wivrn-session.sh manifest link)
#   4. WIVRN_APPLICATION isn't set, so nothing auto-launches on connect
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"

echo "=== container running? ==="
sudo podman ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}' || true

echo ""
echo "=== wivrn-server listening on 9757? ==="
sudo podman exec "$CONTAINER" bash -c "ss -ltn 2>/dev/null | grep 9757 || grep -qi ':26B5' /proc/net/tcp /proc/net/tcp6 && echo 'port 9757 open (hex 26B5)' || echo 'port 9757 NOT open'"

echo ""
echo "=== WiVRn config actually in use (user config overrides /etc) ==="
sudo podman exec "$CONTAINER" bash -c "cat ~/.config/wivrn/config.json 2>/dev/null || echo 'no ~/.config/wivrn/config.json'; echo '--- /etc/wivrn/config.json ---'; cat /etc/wivrn/config.json 2>/dev/null || echo 'no /etc/wivrn/config.json'"

echo ""
echo "=== Steam VR manifest? ==="
sudo podman exec "$CONTAINER" bash -c "
  echo '-- ~/.local/share/Steam/config/steamapps.vrmanifest --'
  ls -l ~/.local/share/Steam/config/steamapps.vrmanifest 2>&1 | head -n 2
  echo '-- ~/.steam/debian-installation/config/steamapps.vrmanifest --'
  ls -l ~/.steam/debian-installation/config/steamapps.vrmanifest 2>&1 | head -n 2
"

echo ""
echo "=== Is Alyx installed? (AppID 546560, BOTH Steam roots) ==="
sudo podman exec "$CONTAINER" bash -c "
  for root in ~/.local/share/Steam ~/.steam/debian-installation ~/.steam/steam; do
    echo \"-- \$root --\"
    ls \$root/steamapps/common/ 2>/dev/null | grep -i alyx || echo '  no Alyx dir in steamapps/common/'
    ls \$root/steamapps/appmanifest_546560.acf 2>/dev/null && echo '  Alyx manifest present' || echo '  no appmanifest_546560.acf'
  done
"

echo ""
echo "=== Steam / gamescope / wivrn-server running? ==="
sudo podman exec "$CONTAINER" bash -c "ps aux | grep -E 'wivrn-server|gamescope|steam' | grep -v grep | awk '{print \$11, \$12, \$13}' | head -n 10 || true"

echo ""
echo "=== Recent container logs (last 40 lines) ==="
sudo podman logs --tail 40 "$CONTAINER" 2>&1 | tail -n 40

echo ""
echo "If Alyx is NOT installed: install it first, then reconnect."
echo "  ./install-alyx.sh   (uses Steam client, NOT steamcmd — steamcmd is not in this image)"
echo "  ./setup-steam.sh"
echo "If Alyx IS installed but picker is still empty: check the manifest lines above."
