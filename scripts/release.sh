#!/bin/bash
# OpenJooki — build everything a release ships, on the Linux bench (root; needs debugfs, e2fsprogs,
# sgdisk, lua5.1, python3). Publishes nothing: scripts/publish-release.sh does, from any machine with gh.
#
#   scripts/release.sh 2.2.6
#
# In: the committed tree (scripts/check_versions.py --release must pass), the 1.3.0 base image
# (OJ_BASE_IMAGE), the pieces of a new card (OJ_NEWCARD: boot.bin, p1.img; OJ_DATA_TAR) and, optionally,
# OJ_FORGET_FILE: one string per line that must not appear in any image (the source Jooki's identity).
# Out, in the repository (ignored by git): release-<V>/ (firmware image + version.json) and
# release-sdcard-<V>/ (new-card image + sdcard.json), both verified.
set -e
cd "$(dirname "$0")/.."
V="$1"; [ -n "$V" ] || { echo "usage: $0 <version>"; exit 1; }
SRC=$(pwd)
WORK=${OJ_WORK:-/root/ojrel}
BASE=${OJ_BASE_IMAGE:-$SRC/run/_rel130/openjooki-firmware-1.3.0.img.gz}
NEWCARD=${OJ_NEWCARD:-/root/newcard}
DATA_TAR=${OJ_DATA_TAR:-$SRC/run/_newcard/data-generic.tar.gz}
FORGET_FILE=${OJ_FORGET_FILE:-$SRC/run/_newcard/forget.txt}
export PATH=/opt/v/bin:/usr/sbin:/sbin:$PATH

say(){ echo; echo "=== $*"; }
for t in debugfs e2fsck sgdisk lua5.1 python3 gzip sha256sum; do command -v $t >/dev/null || { echo "missing tool: $t"; exit 1; }; done
[ -f "$BASE" ] || { echo "base image not found: $BASE (OJ_BASE_IMAGE)"; exit 1; }
[ -f "$NEWCARD/boot.bin" ] && [ -f "$NEWCARD/p1.img" ] || { echo "new-card pieces not found in $NEWCARD (OJ_NEWCARD)"; exit 1; }
[ -f "$DATA_TAR" ] || { echo "data tar not found: $DATA_TAR (OJ_DATA_TAR)"; exit 1; }
python3 scripts/check_versions.py --release "$V"
FORGET=()
if [ -f "$FORGET_FILE" ]; then while read -r s; do [ -n "$s" ] && FORGET+=(--forget "$s"); done < "$FORGET_FILE"; fi

say "copy of the tree to $WORK (Dropbox is slow: a few minutes for the token pictures)"
rm -rf "$WORK"; mkdir -p "$WORK"
cp -r "$SRC/core" "$SRC/tools" "$SRC/scripts" "$WORK/"
find "$WORK" -name '*.sh' -exec sed -i 's/\r$//' {} +
cd "$WORK"

say "core $V (tools/build/bundle.py)"
python3 tools/build/bundle.py --version "$V" --max-kib 400 | tail -n 1

say "firmware image"
python3 scripts/add-webui-to-image.py "$BASE" "$WORK/out-$V.img" "$V" --core build/player.lib "${FORGET[@]}"

say "checks inside the image"
[ "$(debugfs -R 'cat /etc/openjooki-version' "$WORK/out-$V.img" 2>/dev/null)" = "$V" ] || { echo "/etc/openjooki-version is not $V"; exit 1; }
[ "$(grep -ac "var VERSION = '$V'" "$WORK/out-$V.img")" = 1 ] || { echo "the page in the image is not $V"; exit 1; }
debugfs -R "dump /jooki/lib/player.lib /tmp/oj-pl-$V" "$WORK/out-$V.img" 2>/dev/null
cmp -s /tmp/oj-pl-$V build/player.lib || { echo "player.lib in the image differs from the build"; exit 1; }
debugfs -R "dump /jooki/lib/core.lua /tmp/oj-core-$V" "$WORK/out-$V.img" 2>/dev/null
cmp -s /tmp/oj-core-$V build/core.min.lua || { echo "core.lua in the image differs from the build"; exit 1; }
echo "version, page, loader and core verified"

say "release files"
bash scripts/make-release.sh "$WORK/out-$V.img" "$V"
rm -rf "$SRC/release-$V"; mkdir -p "$SRC/release-$V"; cp "release-$V"/* "$SRC/release-$V/"

say "new-card image (tools/sdcard/make_card_image.py)"
mkdir -p "$WORK/card"
python3 tools/sdcard/make_card_image.py --boot "$NEWCARD/boot.bin" --factory "$NEWCARD/p1.img" \
  --rootfs "$SRC/release-$V/openjooki-firmware-$V.img.gz" --version "$V" --out "$WORK/card/openjooki-sdcard-$V.img" \
  --data-tar "$DATA_TAR" "${FORGET[@]}" 2>&1 | tail -n 6
rm -rf "$SRC/release-sdcard-$V"; mkdir -p "$SRC/release-sdcard-$V"
cp "$WORK/card/openjooki-sdcard-$V.img.gz" "$WORK/card/sdcard.json" "$SRC/release-sdcard-$V/"

say "done"
ls -la "$SRC/release-$V" "$SRC/release-sdcard-$V"
cat "$SRC/release-$V/version.json"
echo
echo "next: git push (CI green), then scripts/publish-release.sh $V from a machine with gh; then scripts/check-card.sh $V here."
