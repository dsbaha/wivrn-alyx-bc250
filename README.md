# Half-Life: Alyx in Podman + WiVRn on BC-250

Run Half-Life: Alyx in a Podman container on an AMD BC-250 (repurposed PS5 APU),
streaming to a Meta Quest 3 via WiVRn. No Wolf / Games on Whales, no Docker Compose,
no SteamVR. One container: WiVRn + Steam + gamescope + xrizer + OpenComposite,
plus the BC-250 Vulkan H.264 encoder overlaid.

```
Quest 3 <-> WiFi 5GHz <-> WiVRn in Podman <-> xrizer <-> Proton <-> Alyx <-> BC-250 GPU
```

Alyx never runs on the Quest — the Quest is a thin client. It decodes video,
displays it with TimeWarp, and sends head / controller tracking back.

## What this is / isn't

- **Base:** `ghcr.io/baz00k/gow-collection/wivrn:edge` — WiVRn + Steam in gamescope,
  bypassing Moonlight. Re-used as-is.
- **Overlay:** BC-250 VA-API driver (`bc250_drv_video.so` + shaders) from
  `simpmix/bc250-encoding-decoding-fix`, plus WiVRn env + config for
  2HW + 1SW (left/right eye via HW VA-API, alpha/foveation via SW).
- **Not included:** No game files, no ROMs, no Steam credentials, no Alyx assets.
  You must own Alyx on Steam. Alyx is Steam-only — Steam must be running,
  even in offline mode. There is no supported Steamless Alyx.
- **Image size (checked 2026-10-16):** Base pull ~697 MB / ~2 GB unpacked.
  This overlay adds ~20–50 MB (driver + shaders). Alyx itself is separate,
  ~67 GB in the `wivrn-alyx-steam` named volume, not in the image.

## Prerequisites

- AMD BC-250 machine, headless Fedora CoreOS, Podman (rootful for
  `/dev/uinput` + host networking). No host X server required — gamescope
  provides the virtual display *inside* the container, and `--ipc host`
  is for shared memory / Monado IPC, not for X.
- Meta Quest 3 + WiVRn client app (Meta Horizon Store, search "WiVRn")
- Steam account that owns Half-Life: Alyx
- 5 GHz Wi-Fi, PC wired if possible
- `sudo podman` — rootless Podman struggles with `/dev/uinput` + Avahi mDNS

## Quick start

```bash
git clone https://github.com/dsbaha/wivrn-alyx-bc250.git
cd wivrn-alyx-bc250

# 1. Build (multi-stage: build tools do NOT end up in the final image)
podman build -f Containerfile -t wivrn-alyx:bc250 .

# 2. Verify the BC-250 driver loads BEFORE you ever launch Alyx.
# If vainfo doesn't list BC-250, stop — WiVRn will fall back to software.
podman run --rm --device /dev/dri:/dev/dri \
  -e LIBVA_DRIVER_NAME=bc250 \
  wivrn-alyx:bc250 vainfo --display drm --device /dev/dri/renderD128

# 3. Real H.264 encode via VA-API
podman run --rm --device /dev/dri:/dev/dri \
  -e LIBVA_DRIVER_NAME=bc250 \
  wivrn-alyx:bc250 ffmpeg -vaapi_device /dev/dri/renderD128 \
    -f lavfi -i testsrc=size=1920x1080:rate=60 \
    -vf 'format=nv12,hwupload' -c:v h264_vaapi -b:v 15M -frames:v 300 /tmp/test_enc.mp4

# 4. Run
./run.sh
```

`run.sh` is `sudo podman run` with `--network host --ipc host` (no
`--shm-size` — Podman rejects that combo; with `--ipc host` the container
uses the host's `/dev/shm` directly, so check `df -h /dev/shm` on the host),
devices `/dev/dri`, `/dev/input`, `/dev/uinput`, the caps WiVRn needs,
and named Podman volumes `wivrn-alyx-steam` + `wivrn-alyx-wivrn`
(Fedora CoreOS — no bind mounts to a filesystem path).

For systemd / boot, copy `wivrn-alyx.container` +
`wivrn-alyx-steam.volume` + `wivrn-alyx-wivrn.volume` to
`~/.config/containers/systemd/` and `systemctl --user daemon-reload`.
Same flags, Quadlet form. Inspect volumes with
`sudo podman volume inspect wivrn-alyx-steam`.

## Steam setup — no GUI needed

### Steam Guard

Steam Guard is Valve's 2FA. The container looks like a brand-new device, so
the first login asks for a one-time code from email or the Steam Mobile App
(Steam Guard → 5-character code, refreshes every 30s). After that one login,
it caches a sentry file (`ssfn*`) + auth token in the `wivrn-alyx-steam`
named volume, and later runs skip the prompt as long as you keep that volume.

One-time login:

```bash
podman exec -it wivrn-alyx steamcmd +login <user> <pass> <GuardCode> +quit
# or if it already prompted:
# podman exec -it wivrn-alyx steamcmd +set_steam_guard_code <GuardCode>
```

Treat the `wivrn-alyx-steam` volume as sensitive — it holds auth tokens.

### Alyx Proton + launch options

With Steam stopped in the container, run:

```bash
./setup-steam.sh
```

That edits two files (Steam closed, or it overwrites on exit):

- `config/config.vdf` — `CompatToolMapping` for Alyx (546560) → `GE-Proton9-27`.
  Not Proton 10, not native. The native Linux build exits at startup.
- `userdata/<id>/config/localconfig.vdf` — `LaunchOptions` for Alyx →
  `VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%`

The `/run/host/...` path is intentional — that's how Steam's Pressure Vessel
sees the container's `/usr` inside the game's sandbox. Don't use `/usr/lib64/...` here.

Keep the global OpenComposite default. Don't change `WIVRN_OPENVR_COMPAT_PATH`
globally to xrizer just for Alyx — use the per-game `VR_OVERRIDE` above.

## Quest 3

1. Install WiVRn from the Meta Horizon Store (or sideload the APK from
   `WiVRn/WiVRn-APK`). Client and server must be the same WiVRn version.
2. In the WiVRn app: **disable hand tracking**, wake the physical controllers
   **before** connecting. Hand tracking on + controllers asleep = `ERROR_SESSION_LOST`.
3. Connect to the server — via mDNS if it shows, or Manual / Add server
   with the CoreOS box IP + 9757 if mDNS is broken (manual works fine).
4. Once the headset says "waiting for an application to start", launch
   Alyx from the CoreOS box in a second terminal:

   ```bash
   ./launch-alyx.sh
   ```

   That tells the Steam already running in the container to launch Alyx
   in VR. WiVRn does NOT auto-start a game unless `WIVRN_APPLICATION`
   is set — "waiting for an application" is normal until you launch one.

   NOTE: `WIVRN_APPLICATION` auto-launch was reverted — it broke Quadlet
   parsing and stopped the container from starting, so the server
   never showed on the LAN. Don't re-add it to the Quadlet file.
   Use `./launch-alyx.sh` instead.

### "Pick an application" with an empty list?

That picker lists VR apps from Steam's `steamapps.vrmanifest`. Empty =
Alyx isn't installed, or Steam hasn't created the manifest yet.

On the CoreOS box, run:

```bash
./check-apps.sh
```

It checks: is wivrn-server listening, what WiVRn config is actually in
use, does the Steam VR manifest exist, is Alyx installed
(`appmanifest_546560.acf`), and the last 40 lines of container logs.

If Alyx is NOT installed, install it first, then reconnect:

```bash
podman exec -it wivrn-alyx steamcmd +login <user> <pass> +app_update 546560 validate +quit
# then run ./setup-steam.sh (Proton + VR_OVERRIDE) if you haven't yet
# then restart the container and reconnect from the Quest
```

### "Waiting for an application to start"?

Normal — headset is connected, wivrn-server is up, but no OpenXR app is
running yet. From a second terminal on the CoreOS box:

```bash
./launch-alyx.sh
```

If Alyx falls back to desktop (no HMD image), `setup-steam.sh` didn't
run or LaunchOptions are wrong — see Troubleshooting.

### Server not showing up on the local network?

Discovery is mDNS/Avahi (UDP 5353) + WiVRn on TCP/UDP 9757. Run:

```bash
./check-network.sh
```

It checks: container running, host IP/subnet, 9757 + 5353 listening,
wivrn-server + Avahi inside the container, host firewalld, logs, and
mDNS broadcast. Most common cause on CoreOS: firewalld blocking 5353 /
9757 — Podman `--network host` does NOT add firewall rules. Fix:

```bash
sudo firewall-cmd --permanent --add-port=5353/udp --add-port=9757/tcp --add-port=9757/udp
sudo firewall-cmd --reload
```

If the server is running but discovery is broken, bypass mDNS: in the
Quest WiVRn app use Manual / Add server and type the host IP + 9757.

## How video gets there

Alyx renders left/right eye via Proton → Vulkan → RADV → BC-250 GPU (stays
in VRAM) → WiVRn Monado compositor intercepts at `xrEndFrame`, grabs
VkImage / DMA-BUF, no CPU readback → VA-API → `bc250_drv_video.so` →
Vulkan compute shaders → H.264 bitstream, per-eye separate → UDP 9757
(TCP fallback), mDNS 5353 discovery, Opus audio → Quest 3 hardware decode →
TimeWarp → display. Tracking / controllers come back over the same connection
→ OpenXR → xrizer → Alyx.

BC-250 has no separate VCN — the physical VCN engine is eFused off at the
factory. Encode shares the same 40 CUs as rendering, so expect 72 Hz,
medium settings, moderate bitrate. That's why the overlay defaults to
`BC250_H264_BACKEND=x264` (Zen 2 CPU offload, leaves GPU free for the game)
and `BC250_SLICES_PER_FRAME=2` for VR. Switch `BC250_H264_BACKEND` to
`compute` only if CPU becomes the bottleneck.

No AV1 in the bc250 driver docs (H.264 + HEVC only). AV1 would help bandwidth
but hurts latency, and on BC-250 there is no HW AV1 encoder — it would need
a new Vulkan-compute AV1 encoder stealing CUs from the game. Local 5 GHz
Wi-Fi has bandwidth headroom; latency is the bottleneck, so H.264 wins here.

## Files

- `Containerfile` — multi-stage: builder compiles bc250 driver, final stage
  copies only driver + shaders onto GoW `wivrn:edge`.
- `wivrn-config.json` — WiVRn VA-API, H.264, 50 Mbps.
- `run.sh` — Podman run for Alyx.
- `launch-alyx.sh` — launch Alyx after Quest connects ("waiting for app").
- `check-apps.sh` — diagnose empty "pick an application" picker.
- `check-network.sh` — diagnose server not showing on local network.
- `setup-steam.sh` — one-time Alyx Proton + launch-option edits, no GUI.
- `wivrn-alyx.container` — Quadlet / systemd version of `run.sh`.
- `wivrn-alyx-steam.volume` / `wivrn-alyx-wivrn.volume` — named-volume
  definitions for Quadlet (Fedora CoreOS, no bind mounts).

## Other games

- **Skyrim VR:** Same as Alyx — Steam-only on PC, Steam required. Use
  OpenComposite (not xrizer) for Skyrim VR — xrizer lacks the keyboard
  overlay Skyrim needs at character creation.
- **No Man's Sky:** Different — the GOG copy is DRM-free and can run without
  Steam (launch with `-HmdEnable 1` + OpenComposite → WiVRn). The Steam copy
  still needs Steam.

## Troubleshooting

- "Waiting for an application to start" → no game launched yet. Run
  `./launch-alyx.sh` from the CoreOS box while the headset is connected.
- Server not showing on local network → run `./check-network.sh`.
  Most common: firewalld blocking 5353/9757, or container exited on
  restart (name conflict). Bypass mDNS via Manual / Add server + host IP.
- "Pick an application to start streaming" with empty list → Alyx not
  installed yet, or Steam manifest missing. Run `./check-apps.sh` on the
  CoreOS box. Pick Alyx from the in-headset menu once it's installed.
- `xdg_backend couldn't connect to wayland display` → gamescope was
  trying `--backend wayland` (nested in a host compositor, which Wolf
  provides but headless Podman does not). Fixed in this repo: the
  Containerfile patches `gamescope-lib.sh` to use
  `GAMESCOPE_BACKEND` (default `headless`), and `run.sh` / Quadlet set
  `GAMESCOPE_BACKEND=headless`. Pull latest and rebuild.
- `vainfo` doesn't list BC-250 → check `/dev/dri/renderD128` exists,
  user is in `video` + `render` groups, `LIBVA_DRIVER_NAME=bc250`.
- Game starts on virtual screen, no HMD image / tracking → it fell back to
  desktop mode. Check startup logs for the `VR_OVERRIDE=...` line.
- `IVRSystem_026` error → wrong Proton / OpenComposite combo. Use
  GE-Proton 9-27 + xrizer `VR_OVERRIDE` for Alyx.
- `ERROR_SESSION_LOST` → hand tracking on, or controllers asleep. Turn hand
  tracking off, wake controllers before connecting.
- Don't enable `PROTON_LOG=1` by default — one report produced a 17 GB log.

## Sources

- Base image: `baz00k/gow-collection` — `images/wivrn/README.md`,
  `images/wivrn/docs/wivrn-alyx.md`
- BC-250 driver: `simpmix/bc250-encoding-decoding-fix` — `docs/wivrn-guide.md`,
  `docs/sunshine-guide.md`
- WiVRn: `WiVRn/WiVRn` — `docs/configuration.md`, `docs/steamvr.md`
