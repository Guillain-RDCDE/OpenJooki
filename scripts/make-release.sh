#!/bin/bash
# OpenJooki — prepares a release (compressed image + sha256 + version.json + the updater scripts).
# Usage: make-release.sh <image.img[.gz]> <version>
#
# version.json also gives the sha256 of the updater scripts of this commit (docs/, OJ_DOCS to
# point elsewhere): ota_sha256 and selfupdate_sha256, which o.sh and b.sh check before running
# them, and o_sha256 (o.sh itself). openjooki-ota.sh and openjooki-selfupdate.sh are copied
# next to it: scripts/publish-release.sh attaches them to the release.
set -e
IMG="$1"; VER="$2"; DEVTYPE="${3:-ml-j2000}"
[ -f "$IMG" ] && [ -n "$VER" ] || { echo "usage: make-release.sh <image.img[.gz]> <version> [device_type=ml-j2000]"; exit 1; }
DOCS="${OJ_DOCS:-$(cd "$(dirname "$0")/.." && pwd)/docs}"
for s in o.sh openjooki-ota.sh openjooki-selfupdate.sh; do [ -f "$DOCS/$s" ] || { echo "missing: $DOCS/$s (OJ_DOCS)"; exit 1; }; done
command -v sha256sum >/dev/null 2>&1 && SHA="sha256sum" || SHA="shasum -a 256"
OUT="release-$VER"; mkdir -p "$OUT"
FILE="openjooki-firmware-$VER.img.gz"
case "$IMG" in *.gz) cp "$IMG" "$OUT/$FILE";; *) gzip -c "$IMG" > "$OUT/$FILE";; esac
HASH=$($SHA "$OUT/$FILE" | cut -d' ' -f1)
cp "$DOCS/openjooki-ota.sh" "$DOCS/openjooki-selfupdate.sh" "$OUT/"
OTA_HASH=$($SHA "$OUT/openjooki-ota.sh" | cut -d' ' -f1)
SELF_HASH=$($SHA "$OUT/openjooki-selfupdate.sh" | cut -d' ' -f1)
O_HASH=$($SHA "$DOCS/o.sh" | cut -d' ' -f1)
cat > "$OUT/version.json" <<EOF
{
  "version": "$VER",
  "file": "$FILE",
  "sha256": "$HASH",
  "device_type": "$DEVTYPE",
  "date": "$(date +%Y-%m-%d)",
  "ota_sha256": "$OTA_HASH",
  "selfupdate_sha256": "$SELF_HASH",
  "o_sha256": "$O_HASH"
}
EOF
echo "Release ready in $OUT/ :"; ls -la "$OUT"
echo "→ GitHub Release tag v$VER, attach $FILE, version.json, openjooki-ota.sh AND openjooki-selfupdate.sh."
