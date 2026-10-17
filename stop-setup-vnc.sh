#!/usr/bin/env bash
# Stop the VNC setup container (started by ./setup-vnc.sh).
set -euo pipefail
sudo podman rm -f wivrn-alyx-setup 2>/dev/null || true
echo "VNC setup container stopped."
echo "Next: ./run.sh  (WiVRn play container)"
