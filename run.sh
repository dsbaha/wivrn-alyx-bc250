#!/usr/bin/env bash
# Run wivrn-alyx:bc250 with Podman (rootful).
# Rootful is required for /dev/uinput + host networking + Avahi mDNS.
# Steam data + WiVRn config persist in ./steam-data and ./wivrn-data.
# NOTE: No --shm-size here — Podman rejects it with --ipc host:
# "cannot set shmsize when running in the host ipc namespace".
# With --ipc host the container uses the host's /dev/shm directly,
# so make sure the host's /dev/shm is big enough (check `df -h /dev/shm`;
# if it's small: `sudo mount -o remount,size=8G /dev/shm`).
# GoW's Docker config lists both IpcMode:host + ShmSize:8g, but Podman
# treats that combination as invalid — Docker tolerates it, Podman does not.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p ./steam-data ./wivrn-data

exec sudo podman run --rm -it \
  --name wivrn-alyx \
  --network host \
  --ipc host \
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
