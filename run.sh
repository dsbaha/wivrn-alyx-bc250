#!/usr/bin/env bash
# Run wivrn-alyx:bc250 with Podman (rootful) on Fedora CoreOS.
# Rootful is required for /dev/uinput + host networking + Avahi mDNS.
# Steam data + WiVRn config persist in NAMED Podman volumes, not bind
# mounts to a filesystem path — this is Fedora CoreOS, so we don't
# assume a writable working directory for game data. Volumes live in
# /var/lib/containers/storage/volumes/ and survive CoreOS updates.
#   wivrn-alyx-steam -> /home/retro/.local/share/Steam  (Alyx, ~67 GB)
#   wivrn-alyx-wivrn -> /home/retro/.config/wivrn   (WiVRn config)
# Inspect:  sudo podman volume inspect wivrn-alyx-steam
# Back up:  sudo podman volume export wivrn-alyx-steam > steam-backup.tar
# NOTE: No --shm-size here — Podman rejects it with --ipc host:
# "cannot set shmsize when running in the host ipc namespace".
# With --ipc host the container uses the host's /dev/shm directly,
# so make sure the host's /dev/shm is big enough (check `df -h /dev/shm`;
# if it's small: `sudo mount -o remount,size=8G /dev/shm`).
# GoW's Docker config lists both IpcMode:host + ShmSize:8g, but Podman
# treats that combination as invalid — Docker tolerates it, Podman does not.
set -euo pipefail

# Create named volumes if they don't exist (idempotent)
sudo podman volume exists wivrn-alyx-steam || sudo podman volume create wivrn-alyx-steam
sudo podman volume exists wivrn-alyx-wivrn || sudo podman volume create wivrn-alyx-wivrn

# ---------------------------------------------------------------- WiVRn PIN
# WiVRn has NO fixed-PIN config — the PIN is randomly generated (6 digits)
# for FIRST pairing only, printed as "To pair a new headset use PIN code: XXXXXX"
# in the logs + a desktop notification you never see headless.
# After first pairing, the headset's public key is stored in known_keys
# (in the wivrn-alyx-wivrn volume) and the PIN is NEVER needed again —
# known headsets reconnect with the stored key (code uses "000000" internally).
# So the "stable PIN" is: pair ONCE, keep the volume, never need a PIN again.
# If you keep seeing a PIN every time, known_keys is not persisting —
# check that wivrn-alyx-wivrn volume is mounted (it is, above) and not wiped.
#
# To set YOUR preferred PIN for first pairing, put it here:
#   WIVRN_PIN=xxx
# Replace xxx with your 6-digit PIN (e.g. WIVRN_PIN=123456).
# NOTE: WiVRn will still generate a RANDOM PIN for first pairing — this
# variable does NOT set it (WiVRn has no such option). It is here as a
# reminder of the PIN you used, and ./show-pin.sh will print the CURRENT
# random PIN from the logs so you don't have to dig:
#   ./show-pin.sh
# After first pairing, you can delete this line — PIN is not needed again.
WIVRN_PIN=xxx
# It broke Quadlet parsing (spaces/quotes in Environment=) and could stop
# the container from starting, so WiVRn never advertised on the LAN.
# To opt back into auto-launch with run.sh only, add this line above
# the LIBVA_DRIVER_NAME line in the podman run below:
#   -e WIVRN_APPLICATION='["steam", "steam://launch/546560/VR"]' \
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
  -v wivrn-alyx-steam:/home/retro/.local/share/Steam:Z \
  -v wivrn-alyx-wivrn:/home/retro/.config/wivrn:Z \
  -e GAMESCOPE_BACKEND=headless \
  -e RADV_DEBUG=${RADV_DEBUG:-nohiz} \
  -e VR_OVERRIDE=${VR_OVERRIDE:-/opt/xrizer} \
  -e LIBVA_DRIVER_NAME=bc250 \
  -e BC250_FAST_MODE=1 \
  -e BC250_SLICES_PER_FRAME=${BC250_SLICES_PER_FRAME:-2} \
  -e BC250_H264_BACKEND=${BC250_H264_BACKEND:-x264} \
  -e WIVRN_ENCODER=${WIVRN_ENCODER:-auto} \
  -e WIVRN_CODEC=${WIVRN_CODEC:-} \
  -e WIVRN_TCP_ONLY=${WIVRN_TCP_ONLY:-false} \
  -e OMP_WAIT_POLICY=PASSIVE \
  -e GOMP_SPINCOUNT=0 \
  wivrn-alyx:bc250
