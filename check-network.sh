#!/usr/bin/env bash
# Deep diagnose "WiVRn discovery still not working" — server not showing
# in the Quest app. Run this on the CoreOS box and paste the whole output.
# Discovery = mDNS/Avahi (UDP 5353, publish-service=avahi) + WiVRn 9757.
# This script does NOT fix anything — it shows what is actually happening.
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"

echo "=== 0. Did you REBUILD after the last git pull? (Containerfile changes need a rebuild) ==="
sudo podman images wivrn-alyx:bc250 --format '{{.ID}} {{.Created}} {{.Size}}' || echo "No wivrn-alyx:bc250 image"
echo "-- Does the image contain the headless patch? --"
sudo podman run --rm wivrn-alyx:bc250 grep -o 'GAMESCOPE_BACKEND[^"]*' /opt/gow/gamescope-lib.sh 2>&1 | head -n 2 || echo "PATCH MISSING — you are running an old image. Rebuild: podman build -f Containerfile -t wivrn-alyx:bc250 ."
echo "-- Does the image still contain WIVRN_APPLICATION in Quadlet? (should be gone) --"
grep -n WIVRN_APPLICATION wivrn-alyx.container run.sh 2>/dev/null || echo "WIVRN_APPLICATION not in run files (good — reverted)"

echo ""
echo "=== 1. Container running? ==="
sudo podman ps -a --filter name="$CONTAINER" --format '{{.Names}} {{.Status}} {{.Image}}' || true

echo ""
echo "=== 1b. Quadlet unit (if you use Quadlet) ==="
systemctl --user status wivrn-alyx.service --no-pager 2>&1 | head -n 25 || true

echo ""
echo "=== 2. Host IP (Quest must be same subnet) ==="
ip -4 addr show scope global | grep -E 'inet |^[0-9]+:' || true
hostname -I 2>/dev/null || true

echo ""
echo "=== 3. Who is listening on 9757 / 5353? (with --network host, container = host net) ==="
echo "-- 9757 TCP --"
sudo ss -lntup 2>/dev/null | grep 9757 || echo "NOTHING on 9757 TCP — wivrn-server NOT listening"
echo "-- 9757 UDP --"
sudo ss -lnup 2>/dev/null | grep 9757 || echo "NOTHING on 9757 UDP"
echo "-- 5353 UDP (mDNS) — WHO owns it? --"
sudo ss -lnup 2>/dev/null | grep 5353 || echo "NOTHING on 5353 — Avahi NOT listening"
echo "-- Host Avahi daemon (conflicts with container Avahi on --network host) --"
ps aux | grep -E 'avahi-daemon' | grep -v grep || echo "No host avahi-daemon running (good — container Avahi can bind 5353)"

echo ""
echo "=== 4. Inside container: processes + effective WiVRn config ==="
if sudo podman ps --filter name="$CONTAINER" --format '{{.Names}}' | grep -q .; then
  sudo podman exec "$CONTAINER" bash -c "ps aux | grep -E 'wivrn-server|avahi-daemon|gamescope|steam' | grep -v grep || echo 'NO wivrn-server/avahi/gamescope/steam in container'"
  echo "-- ~/.config/wivrn/config.json (user, wins over /etc) --"
  sudo podman exec "$CONTAINER" bash -c "cat ~/.config/wivrn/config.json 2>/dev/null || echo 'NO user config'"
  echo "-- /etc/wivrn/config.json --"
  sudo podman exec "$CONTAINER" bash -c "cat /etc/wivrn/config.json 2>/dev/null || echo 'NO /etc config'"
  echo "-- GAMESCOPE_BACKEND actually in container env? --"
  sudo podman exec "$CONTAINER" bash -c "echo GAMESCOPE_BACKEND=\$GAMESCOPE_BACKEND; grep -o 'backend.*' /opt/gow/gamescope-lib.sh | head -n 1"
else
  echo "Container NOT running — skipping in-container checks. See section 6 logs."
fi

echo ""
echo "=== 5. Firewall (you said no firewall problem — just showing state) ==="
if command -v firewall-cmd >/dev/null 2>&1; then
  sudo firewall-cmd --state 2>&1 || true
  sudo firewall-cmd --list-ports 2>&1 || true
else
  echo "firewall-cmd not found"
fi

echo ""
echo "=== 6. Container logs — filtered for the failure (last 150 lines) ==="
sudo podman logs --tail 150 "$CONTAINER" 2>&1 | grep -iE 'avahi|publish|wivrn|gamescope|backend|wayland|xdg|error|fail|bind|address already|permission|denied|exit|crash' | tail -n 60 || echo "(no matching log lines — showing raw tail)"
echo "--- raw tail 30 ---"
sudo podman logs --tail 30 "$CONTAINER" 2>&1 | tail -n 30 || true

echo ""
echo "=== 7. mDNS from host — can the host see the WiVRn service? ==="
if command -v avahi-browse >/dev/null 2>&1; then
  timeout 6 avahi-browse -rt _wivrn._tcp 2>&1 || echo "No _wivrn._tcp seen via avahi-browse"
else
  echo "avahi-browse not on host"
fi

echo ""
echo "=== 8. Manual-connect bypass (proves server is up even if mDNS is dead) ==="
echo "In the Quest WiVRn app: Manual / Add server -> IP from section 2 + port 9757."
echo "If manual works, the problem is ONLY mDNS publish (Avahi). If manual"
echo "also fails, wivrn-server itself is not listening (section 3) or the"
echo "container exited (section 1/6)."
