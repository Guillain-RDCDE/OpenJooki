#!/bin/ash
# OpenJooki — UPDATE entrypoint. Run ON a Jooki that already has OpenJooki.
# Self-contained: pulls the updater scripts of the latest release (checked against the
# sha256 its version.json gives, see below), then checks that release for a newer firmware
# and installs it safely (A/B partition + armed U-Boot rollback). It CANNOT brick the
# device, and if you are already on the latest version it simply does nothing.
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
# The updater scripts, checked before anything runs. The release's version.json gives their
# sha256 (ota_sha256, selfupdate_sha256, written by scripts/make-release.sh). Each script is
# taken from the release, or from Pages when the release has no copy with that sha256, and
# replaces the old one only once both are right. A release made before these fields existed
# gets the Pages copies as it always did, unchecked, and the log says so.
dl "$BASE/version.json" "$WORK/version.json" || { st "ERROR: cannot reach GitHub — nothing changed"; exit 1; }
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
    st "ERROR: cannot reach GitHub — nothing changed"; exit 1
  fi
  mv -f "$WORK/ota.sh.new" "$WORK/ota.sh" && mv -f "$WORK/selfupdate.sh.new" "$WORK/selfupdate.sh" || { st "ERROR: cannot write $WORK — nothing changed"; exit 1; }
  st "updater verified (sha256 given by the release)"
else
  st "updater not verified (this release gives no sha256 for it)"
  dl "$PAGES/openjooki-ota.sh" "$WORK/ota.sh" || { st "ERROR: cannot reach GitHub — nothing changed"; exit 1; }
  dl "$PAGES/openjooki-selfupdate.sh" "$WORK/selfupdate.sh" || { st "ERROR: download failed — nothing changed"; exit 1; }
fi
chmod +x "$WORK/ota.sh" "$WORK/selfupdate.sh"

sh "$WORK/ota.sh" >> "$STATUS" 2>&1
RC=$?
# ota.sh reboots on a successful install, so on return RC=0 means "already current".
if [ "$RC" = "0" ]; then st "already up to date — nothing to install."; fi
exit "$RC"
