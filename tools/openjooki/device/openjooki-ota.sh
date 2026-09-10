#!/bin/ash
# OpenJooki — update from GitHub, run ON the Jooki.
# Simple and safe: downloads the latest release, verifies the sha256, installs A/B
# (writing to the spare partition + armed U-Boot rollback). Cannot brick it.
#
# Usage: openjooki-ota.sh [--check]
#   (no arg): checks, downloads and installs if there's anything new (reboots at the end).
#   --check  : only reports whether a new version exists, installs nothing.

REPO="Guillain-RDCDE/OpenJooki"
BASE="https://github.com/$REPO/releases/latest/download"
WORK="/data/openjooki"
SELF="/data/openjooki/selfupdate.sh"
mkdir -p "$WORK"
log(){ echo "[ota] $*"; }
dl(){ _u="$1"; _o="$2"; _i=0; while :; do curl -fSL --max-time 1200 "$_u" -o "$_o" && return 0; _i=$((_i+1)); [ $_i -ge 5 ] && return 1; log "network hiccup, retry $_i/5…"; sleep 5; done; }

# Currently installed version = the one recorded in the running firmware.
CUR=$(cat /etc/openjooki-version 2>/dev/null || echo "0")

log "fetching manifest (version.json)…"
dl "$BASE/version.json" "$WORK/version.json" || { log "no network or no release"; exit 1; }

# Tiny JSON parser in sed (no jq on the device).
VER=$(sed -n 's/.*"version"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
FILE=$(sed -n 's/.*"file"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
SHA=$(sed -n 's/.*"sha256"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
[ -n "$VER" ] && [ -n "$FILE" ] && [ -n "$SHA" ] || { log "invalid manifest"; exit 1; }

# Hardware-model safety gate: compare our device model to the manifest's.
DEVDT=$(cat /data/mender/device_type 2>/dev/null || cat /var/lib/mender/device_type 2>/dev/null || cat /etc/mender/device_type 2>/dev/null)
DEVDT=${DEVDT##*=}
MANDT=$(sed -n 's/.*"device_type"[^"]*"\([^"]*\)".*/\1/p' "$WORK/version.json" | head -n 1)
if [ -n "$MANDT" ]; then
  [ -n "$DEVDT" ] || { log "SAFETY: cannot read device model — aborting"; exit 1; }
  [ "$DEVDT" = "$MANDT" ] || { log "SAFETY: this release targets '$MANDT' but device is '$DEVDT' — wrong model, aborting"; exit 1; }
  log "device model OK: $DEVDT"
fi

log "available version: $VER   (installed: $CUR)"
if [ "$VER" = "$CUR" ]; then log "already up to date."; exit 0; fi
if [ "$1" = "--check" ]; then log "UPDATE AVAILABLE: $VER"; exit 10; fi

log "downloading $FILE…"
dl "$BASE/$FILE" "$WORK/$FILE" || { log "download failed"; exit 1; }

log "verifying sha256…"
GOT=$(sha256sum "$WORK/$FILE" | cut -d' ' -f1)
if [ "$GOT" != "$SHA" ]; then
  log "INVALID SHA256 ($GOT != $SHA) — image rejected, nothing installed."
  rm -f "$WORK/$FILE"; exit 3
fi
log "image intact (sha256 OK)."

if [ ! -x "$SELF" ]; then
  log "fetching updater (selfupdate.sh)…"
  dl "$BASE/openjooki-selfupdate.sh" "$SELF" && chmod +x "$SELF"
fi
[ -x "$SELF" ] || { log "selfupdate.sh not found"; exit 4; }
log "A/B install (spare partition, armed rollback)…"
sh "$SELF" "$WORK/$FILE"
log "install not performed (see messages above)."
exit 5
