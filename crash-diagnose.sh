#!/usr/bin/env bash
# Diagnose "Alyx launched and crashed the machine" (BC-250, headless CoreOS).
# BC-250 has 16GB unified GDDR6 (CPU + GPU share it). Alyx + Proton + WiVRn +
# gamescope + Steam can OOM it, or the GPU can hang if encode + render fight
# for the same 40 CUs. This collects: uptime (did it reboot?), previous-boot
# journal (what killed it), OOM / GPU hang / thermal lines, container state.
#
# Usage: ./crash-diagnose.sh
#   Run AFTER the machine is back up (SSH). Paste the output.
set -euo pipefail

echo "=== 1. Is this a fresh boot after a crash? ==="
uptime
echo "Boot time: $(who -b 2>/dev/null || echo 'unknown')"
echo "Kernel: $(uname -r)"

echo ""
echo "=== 2. Previous boot — last 80 lines (what happened before the crash) ==="
sudo journalctl -b -1 -e --no-pager 2>&1 | tail -n 80 || echo "(no previous boot journal — journal may not persist on CoreOS, or this is the first boot)"

echo ""
echo "=== 3. OOM killer? (previous boot + current) ==="
sudo journalctl -b -1 --no-pager 2>&1 | grep -iE 'out of memory|oom-killer|killed process' | tail -n 20 || echo "(no OOM in previous boot)"
sudo dmesg 2>&1 | grep -iE 'out of memory|oom-killer' | tail -n 20 || echo "(no OOM in current dmesg)"

echo ""
echo "=== 4. GPU hang / amdgpu errors? ==="
sudo journalctl -b -1 --no-pager 2>&1 | grep -iE 'amdgpu|gpu.*hang|ring.*timeout|drm.*error|vcn|reset' | tail -n 40 || echo "(no GPU lines in previous boot)"
sudo dmesg 2>&1 | grep -iE 'amdgpu|gpu.*hang|ring.*timeout|drm.*error' | tail -n 20 || echo "(no GPU lines in current dmesg)"

echo ""
echo "=== 5. Thermal / power? ==="
sensors 2>/dev/null | head -n 30 || echo "(no sensors output — lm_sensors may not be installed)"
sudo journalctl -b -1 --no-pager 2>&1 | grep -iE 'thermal|temperature|critical|shutdown|power' | tail -n 20 || echo "(no thermal/power lines)"

echo ""
echo "=== 6. Containers now ==="
sudo podman ps -a --format '{{.Names}} {{.Status}}' || echo "(podman ps failed)"

echo ""
echo "=== 7. Container logs (last 50 lines, if container still exists) ==="
sudo podman logs --tail 50 wivrn-alyx 2>&1 | tail -n 50 || echo "(no wivrn-alyx logs)"

echo ""
echo "=== 8. Memory / disk now ==="
free -h
df -h /var/lib/containers /dev/shm 2>/dev/null | head -n 10
echo ""
echo "If OOM: Alyx on BC-250 needs low settings + 72Hz + moderate bitrate —"
echo "16GB unified RAM is the hard limit. If GPU hang: try BC250_H264_BACKEND=x264"
echo "(already default — CPU offload, leaves GPU free) + lower WiVRn bitrate."
echo "Paste sections 2-4 — they show whether it was OOM, GPU hang, or thermal."
