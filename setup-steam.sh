#!/usr/bin/env bash
# One-time Steam setup for Alyx, no GUI needed.
# Run AFTER first container start, with Steam stopped in the container.
#   ./setup-steam.sh
# Requires: podman, a running wivrn-alyx container, Steam already logged in once
# (see README.md "Steam Guard" for the one-time login).
#
# What this does:
#  - Sets Alyx (546560) CompatToolMapping to GE-Proton9-27 in config.vdf
#  - Sets Alyx LaunchOptions to xrizer VR_OVERRIDE in localconfig.vdf
# It edits the VDF files with Python (stdlib only), with Steam closed.
set -euo pipefail

CONTAINER="${CONTAINER:-wivrn-alyx}"
STEAM_HOME="/home/retro/.local/share/Steam"

# Find the userdata dir (your Steam user id)
USER_ID=$(podman exec "$CONTAINER" bash -c "ls $STEAM_HOME/userdata | head -n 1")
echo "Steam userdata id: $USER_ID"

podman exec "$CONTAINER" python3 - <<'PYEOF'
import re, pathlib

steam = pathlib.Path("/home/retro/.local/share/Steam")
config_vdf = steam / "config" / "config.vdf"
# localconfig.vdf lives under userdata/<id>/config/
locals_ = list((steam / "userdata").glob("*/config/localconfig.vdf"))
if not locals_:
    raise SystemExit("localconfig.vdf not found — has Steam run once in the container?")
localconfig_vdf = locals_[0]
print(f"config.vdf: {config_vdf}")
print(f"localconfig.vdf: {localconfig_vdf}")

# --- config.vdf: CompatToolMapping for Alyx -> GE-Proton9-27 ---
text = config_vdf.read_text()
# Insert or replace the 546560 block inside CompatToolMapping.
# This is a targeted text edit, not a full VDF round-trip.
alyx_block = '"546560"\n\t\t\t{\n\t\t\t\t"name"\t\t"GE-Proton9-27"\n\t\t\t\t"config"\t\t""\n\t\t\t\t"priority"\t\t"250"\n\t\t\t}'
if '"546560"' in text:
    # Replace existing block (non-greedy up to its closing brace at same indent)
    text = re.sub(r'"546560"\s*\{[^}]*\}', alyx_block, text, count=1)
else:
    # Insert inside CompatToolMapping if it exists, else create it
    if '"CompatToolMapping"' in text:
        text = text.replace('"CompatToolMapping"\n\t\t{',
                            '"CompatToolMapping"\n\t\t{\n\t\t\t' + alyx_block, 1)
    else:
        print("WARNING: no CompatToolMapping section found — check config.vdf manually")
        raise SystemExit(1)
config_vdf.write_text(text)
print("Wrote CompatToolMapping for 546560 -> GE-Proton9-27")

# --- localconfig.vdf: LaunchOptions for Alyx -> xrizer ---
text2 = localconfig_vdf.read_text()
launch = 'VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%'
alyx_launch = f'"546560"\n\t\t\t{{\n\t\t\t\t"LaunchOptions"\t\t"{launch}"\n\t\t\t}}'
if '"546560"' in text2:
    # If Alyx already has a block, replace/insert LaunchOptions inside it
    if 'LaunchOptions' in text2:
        text2 = re.sub(r'("546560"\s*\{[^}]*?"LaunchOptions"\s*")[^"]*(")',
                       r'\g<1>' + launch + r'\g<2>', text2, count=1, flags=re.DOTALL)
    else:
        text2 = re.sub(r'("546560"\s*\{)', r'\1\n\t\t\t\t"LaunchOptions"\t\t"' + launch + '"', text2, count=1)
else:
    # Insert under "Apps" if present
    if '"Apps"' in text2:
        text2 = text2.replace('"Apps"\n\t\t{', '"Apps"\n\t\t{\n\t\t\t' + alyx_launch, 1)
    else:
        print("WARNING: no Apps section in localconfig.vdf — check file manually")
        raise SystemExit(1)
localconfig_vdf.write_text(text2)
print(f"Wrote LaunchOptions for 546560 -> {launch}")
PYEOF

echo "Done. Restart the container and launch Alyx from the Quest WiVRn menu."
