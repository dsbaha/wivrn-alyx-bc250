#!/usr/bin/env bash
# Run wivrn-alyx:bc250 with Podman (rootful).
# Rootful is required for /dev/uinput + host networking + Avahi mDNS.
# Steam data + WiVRn config persist in ./steam-data and ./wivrn-data.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p ./steam-data ./wivrn-data

exec sudo podman run --rm -it \
  --name wivrn-alyx \
  --network host \
  --ipc host \
  --shm-size 8g \
  --device /dev/dri:/dev/dri \
  --device /dev/input:/dev/input \
  --device /dev/uinput:/dev/uinput \
  --cap-add SYS_ADMIN,SYS_NICE,SYS_PTRACE,NET_RAW,MKNOD,NET_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --device-cgroup-rule 'c 13:* rwm' \
  --device-cgroup-rule 'c 244:* rwm' \
  -v "$PWD/steam-data:/home/retro/.local/share/Steam:Z" \
  -v "$PWD/wivrn-data:/home/retro/.config/wivrn:Z" \
  -e LIBVA_DRIVER_NAME=bc250 \
  -e BC250_FAST_MODE=1 \
  -e BC250_SLICES_PER_FRAME=2 \
  -e BC250_H264_BACKEND=x264 \
  -e OMP_WAIT_POLICY=PASSIVE \
  -e GOMP_SPINCOUNT=0 \
  wivrn-alyx:bc250
