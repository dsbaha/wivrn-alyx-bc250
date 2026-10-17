#!/usr/bin/env bash
# Diagnose "WiVRn server not showing up on the local network" in the Quest app.
# Discovery is mDNS/Avahi (UDP 5353) + WiVRn on TCP/UDP 9757.
# If the server was visible before and isn't now, almost always one of:
#   1. Container isn't running / crashed on restart (name conflict, bad env)
#   2. wivrn-server / Avahi didn't start inside the container
#   3. Host firewall (firewalld) blocking 5353 / 9757 — Podman --network host
#      does NOT add firewall rules, host firewall still applies
#   4. Quest + PC on different subnets / AP isolation / 2.4 vs 5 GHz split
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"

echo "=== 1. Is the container actually running? ==="
sudo podman ps -a --filter name="$CONTAINER" --format '{{.Names}} {{.Status}} {{.Image}}' || true
echo "(If you see 'Exited' above, the restart failed — see section 6 logs.)"
echo "(If you see a second container with the same name, the old one is still"
echo " holding the name — 'podman rm -f wivrn-alyx' then re-run ./run.sh.)"

echo ""
echo "=== 1b. Quadlet / systemd unit status (if you use Quadlet) ==="
systemctl --user status wivrn-alyx.service --no-pager 2>&1 | head -n 20 || true
echo "(If the unit is 'failed' or 'bad-setting', the .container file failed"
echo " to parse — e.g. an unquoted Environment= with spaces/quotes. Pull"
echo " latest, copy the fixed .container file, daemon-reload, restart.)"
ip -4 addr show scope global | grep -E 'inet |^[0-9]+:' || true
hostname -I 2>/dev/null || true

echo ""
echo "=== 3. Ports listening on HOST (with --network host, container = host net) ==="
echo "-- 9757 (WiVRn) --"
sudo ss -lntup 2>/dev/null | grep 9757 || echo "NOTHING on 9757 — wivrn-server not listening"
echo "-- 5353 (mDNS/Avahi) --"
sudo ss -lnup 2>/dev/null | grep 5353 || echo "NOTHING on 5353 — Avahi not listening"

echo ""
echo "=== 4. Inside container: wivrn-server + avahi-daemon running? ==="
if sudo podman ps --filter name="$CONTAINER" --format '{{.Names}}' | grep -q .; then
  sudo podman exec "$CONTAINER" bash -c "ps aux | grep -E 'wivrn-server|avahi-daemon' | grep -v grep || echo 'wivrn-server / avahi NOT running in container'"
  sudo podman exec "$CONTAINER" bash -c "cat ~/.config/wivrn/config.json 2>/dev/null; echo '---'; cat /etc/wivrn/config.json 2>/dev/null || true"
else
  echo "Container not running — skipping in-container checks."
fi

echo ""
echo "=== 5. Host firewall (firewalld) — most common 'was working, now gone' ==="
if command -v firewall-cmd >/dev/null 2>&1; then
  sudo firewall-cmd --state 2>&1 || true
  sudo firewall-cmd --list-ports 2>&1 || true
  sudo firewall-cmd --list-services 2>&1 || true
  echo ""
  echo "If 5353/udp and 9757/tcp+udp are NOT in the list above, open them:"
  echo "  sudo firewall-cmd --permanent --add-port=5353/udp --add-port=9757/tcp --add-port=9757/udp"
  echo "  sudo firewall-cmd --reload"
else
  echo "firewall-cmd not found — check iptables/nftables manually."
fi

echo ""
echo "=== 6. Container logs (last 50 lines — look for crash / bind errors) ==="
sudo podman logs --tail 50 "$CONTAINER" 2>&1 | tail -n 50 || true

echo ""
echo "=== 7. mDNS broadcast check (from host) ==="
if command -v avahi-browse >/dev/null 2>&1; then
  timeout 5 avahi-browse -rt _wivrn._tcp 2>&1 || echo "No _wivrn._tcp services seen via avahi-browse"
else
  echo "avahi-browse not on host — install avahi-tools, or check from another machine:"
  echo "  avahi-browse -rt _wivrn._tcp"
fi

echo ""
echo "=== Workarounds if discovery is broken but the server is running ==="
echo "1. In the Quest WiVRn app, use Manual / Add server and type the host IP"
echo "   from section 2 above + port 9757 (bypasses mDNS entirely)."
echo "2. If firewall was the cause, open the ports (section 5) and reconnect."
echo "3. If the container exited, fix the crash in section 6, then:"
echo "   sudo podman rm -f $CONTAINER; ./run.sh"
