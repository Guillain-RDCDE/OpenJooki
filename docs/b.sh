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
PAGES="https://guillain-rdcde.github.io/OpenJooki"
WORK="/data/openjooki"
WEB="/jooki/app/www/public"
STATUS="$WEB/openjooki-status.txt"
mkdir -p "$WORK"
# one install at a time: a link opened twice (or fetched ahead by the browser) starts this twice
if ! mkdir /tmp/openjooki-install 2>/dev/null; then
  echo "[openjooki] already running: this second start does nothing" >> "$STATUS" 2>/dev/null; exit 0
fi
trap 'rmdir /tmp/openjooki-install 2>/dev/null' EXIT
: > "$STATUS" 2>/dev/null
# the factory web server only serves the links put in /tmp/web_ctrl_dirs/public at start: link this one too
[ -d /tmp/web_ctrl_dirs/public ] && ln -sf "$STATUS" /tmp/web_ctrl_dirs/public/ 2>/dev/null
st(){ echo "[openjooki] $*"; echo "[openjooki] $*" >> "$STATUS" 2>/dev/null; }
# curl's own words go to the log: "network hiccup" alone cannot tell a cut from a refused certificate
dl(){ _u="$1"; _o="$2"; _i=0; while :; do _e=$(curl -fsSL -S --max-time 300 "$_u" -o "$_o" 2>&1) && return 0; _i=$((_i+1)); [ $_i -ge 5 ] && { st "$_e"; return 1; }; st "network hiccup (${_e:-no reason given}), retry $_i/5…"; sleep 5; done; }

st "starting first-install…"

# --- Hardware-model gate: Jooki v2 only ---
DT=$(cat /data/mender/device_type 2>/dev/null || cat /var/lib/mender/device_type 2>/dev/null || cat /etc/mender/device_type 2>/dev/null)
DT=${DT##*=}
if [ -z "$DT" ]; then st "ERROR: cannot read device model — aborting (nothing changed)"; exit 2; fi
if [ "$DT" != "ml-j2000" ]; then st "ERROR: this is a '$DT', OpenJooki is for the Jooki v2 (ml-j2000) — aborting (nothing changed)"; exit 2; fi
st "device OK: Jooki v2 ($DT)"

# --- Fetch the OpenJooki updater scripts, checked before anything runs ---
# The release's version.json gives their sha256 (ota_sha256, selfupdate_sha256, written by
# scripts/make-release.sh). Each script is taken from the release, or from Pages when the
# release has no copy with that sha256, and replaces the old one only once both are right.
# A release made before these fields existed gets the Pages copies as it always did,
# unchecked, and the log says so. (o.sh does the same, in the same words.)
st "downloading the OpenJooki updater…"
dl "$BASE/version.json" "$WORK/version.json" || { st "ERROR: no internet / cannot reach GitHub — aborting (nothing changed)"; exit 1; }
OTA_SHA=$(sed -n 's/.*"ota_sha256"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
SELF_SHA=$(sed -n 's/.*"selfupdate_sha256"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
# get NAME FILE SHA256: 0 = FILE has it; 1 = no copy could be downloaded; 3 = no copy had it (FILE removed)
get(){ _r=1; for _from in "$BASE" "$PAGES"; do
    rm -f "$2"
    if [ "$_from" = "$BASE" ]; then curl -fsSL --max-time 300 "$_from/$1" -o "$2"; else dl "$_from/$1" "$2"; fi || continue
    _r=3; [ "$(sha256sum "$2" | cut -d' ' -f1)" = "$3" ] && return 0
  done; rm -f "$2"; return $_r; }
if [ -n "$OTA_SHA" ] && [ -n "$SELF_SHA" ]; then
  get openjooki-ota.sh "$WORK/ota.sh.new" "$OTA_SHA" && get openjooki-selfupdate.sh "$WORK/selfupdate.sh.new" "$SELF_SHA"
  RC=$?
  if [ "$RC" != "0" ]; then
    rm -f "$WORK/ota.sh.new" "$WORK/selfupdate.sh.new"
    [ "$RC" = "3" ] && { st "ERROR: updater rejected, nothing changed (its sha256 is not the release's)"; exit 3; }
    st "ERROR: no internet / cannot reach GitHub — aborting (nothing changed)"; exit 1
  fi
  mv -f "$WORK/ota.sh.new" "$WORK/ota.sh" && mv -f "$WORK/selfupdate.sh.new" "$WORK/selfupdate.sh" || { st "ERROR: cannot write $WORK — aborting (nothing changed)"; exit 1; }
  st "updater verified (sha256 given by the release)"
else
  st "updater not verified (this release gives no sha256 for it)"
  dl "$PAGES/openjooki-ota.sh" "$WORK/ota.sh" || { st "ERROR: no internet / cannot reach GitHub — aborting (nothing changed)"; exit 1; }
  dl "$PAGES/openjooki-selfupdate.sh" "$WORK/selfupdate.sh" || { st "ERROR: download failed — aborting (nothing changed)"; exit 1; }
fi
chmod +x "$WORK/ota.sh" "$WORK/selfupdate.sh"
st "updater ready"

# --- Run the full OTA install (downloads firmware, verifies sha256, A/B installs, reboots) ---
st "downloading & installing firmware — a few minutes, DO NOT UNPLUG…"
sh "$WORK/ota.sh" >> "$STATUS" 2>&1
RC=$?
# ota.sh reboots the device on success, so normally we never get here.
st "install did not complete (code $RC). Your Jooki is UNCHANGED and still works. You can retry."
exit "$RC"
