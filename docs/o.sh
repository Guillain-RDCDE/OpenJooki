#!/bin/ash
# OpenJooki — UPDATE entrypoint. Run ON a Jooki that already has OpenJooki.
# Self-contained: always pulls the newest updater scripts from the GitHub
# release, then checks for a newer firmware and installs it safely
# (A/B partition + armed U-Boot rollback). It CANNOT brick the device, and
# if you are already on the latest version it simply does nothing.
REPO="Guillain-RDCDE/OpenJooki"
BASE="https://github.com/$REPO/releases/latest/download"
PAGES="https://guillain-rdcde.github.io/OpenJooki"
WORK="/data/openjooki"
WEB="/jooki/app/www/public"
STATUS="$WEB/openjooki-status.txt"
mkdir -p "$WORK"
: > "$STATUS" 2>/dev/null
st(){ echo "[openjooki-update] $*"; echo "[openjooki] $*" >> "$STATUS" 2>/dev/null; }
dl(){ _u="$1"; _o="$2"; _i=0; while :; do curl -fsSL --max-time 300 "$_u" -o "$_o" && return 0; _i=$((_i+1)); [ $_i -ge 5 ] && return 1; st "network hiccup, retry $_i/5…"; sleep 5; done; }

st "checking for updates…"
dl "$PAGES/openjooki-ota.sh" "$WORK/ota.sh" || { st "ERROR: cannot reach GitHub — nothing changed"; exit 1; }
dl "$PAGES/openjooki-selfupdate.sh" "$WORK/selfupdate.sh" || { st "ERROR: download failed — nothing changed"; exit 1; }
chmod +x "$WORK/ota.sh" "$WORK/selfupdate.sh"

sh "$WORK/ota.sh" >> "$STATUS" 2>&1
RC=$?
# ota.sh reboots on a successful install, so on return RC=0 means "already current".
if [ "$RC" = "0" ]; then st "already up to date — nothing to install."; fi
exit "$RC"
