#!/bin/ash
# OpenJooki — FIRST-INSTALL bootstrap. Run ON a factory Jooki v2 (no PC needed).
# Self-contained: pulls the OpenJooki updater + firmware from GitHub and installs
# it safely (A/B partition + armed U-Boot rollback). It CANNOT brick the device:
# the running system is never overwritten, and if the new one fails to boot the
# bootloader returns to the old one on its own.
#
# Progress is written to the web root so a phone browser can watch it live at
#   http://<jooki-ip>/openjooki-status.txt
REPO="Guillain-RDCDE/OpenJooki"
BASE="https://github.com/$REPO/releases/latest/download"
WORK="/data/openjooki"
WEB="/jooki/app/www/public"
STATUS="$WEB/openjooki-status.txt"
mkdir -p "$WORK"
: > "$STATUS" 2>/dev/null
st(){ echo "[openjooki] $*"; echo "[openjooki] $*" >> "$STATUS" 2>/dev/null; }
dl(){ _u="$1"; _o="$2"; _i=0; while :; do curl -fsSL --max-time 300 "$_u" -o "$_o" && return 0; _i=$((_i+1)); [ $_i -ge 5 ] && return 1; st "network hiccup, retry $_i/5…"; sleep 5; done; }

st "starting first-install…"

# --- Hardware-model gate: Jooki v2 only ---
DT=$(cat /data/mender/device_type 2>/dev/null || cat /var/lib/mender/device_type 2>/dev/null || cat /etc/mender/device_type 2>/dev/null)
DT=${DT##*=}
if [ -z "$DT" ]; then st "ERROR: cannot read device model — aborting (nothing changed)"; exit 2; fi
if [ "$DT" != "ml-j2000" ]; then st "ERROR: this is a '$DT', OpenJooki is for the Jooki v2 (ml-j2000) — aborting (nothing changed)"; exit 2; fi
st "device OK: Jooki v2 ($DT)"

# --- Fetch the OpenJooki updater scripts (from the GitHub release) ---
st "downloading the OpenJooki updater…"
dl "$BASE/openjooki-ota.sh" "$WORK/ota.sh" || { st "ERROR: no internet / cannot reach GitHub — aborting (nothing changed)"; exit 1; }
dl "$BASE/openjooki-selfupdate.sh" "$WORK/selfupdate.sh" || { st "ERROR: download failed — aborting (nothing changed)"; exit 1; }
chmod +x "$WORK/ota.sh" "$WORK/selfupdate.sh"
st "updater ready"

# --- Run the full OTA install (downloads firmware, verifies sha256, A/B installs, reboots) ---
st "downloading & installing firmware — a few minutes, DO NOT UNPLUG…"
sh "$WORK/ota.sh" >> "$STATUS" 2>&1
RC=$?
# ota.sh reboots the device on success, so normally we never get here.
st "install did not complete (code $RC). Your Jooki is UNCHANGED and still works. You can retry."
exit "$RC"
