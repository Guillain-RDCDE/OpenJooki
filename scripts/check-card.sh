#!/bin/bash
# OpenJooki — after scripts/publish-release.sh: the SD card tool fetches the new-card image from the
# real GitHub release and writes an 8 GB "card" (a file), which is then checked like a real one.
# Linux, root (losetup, sgdisk, e2fsck).
#   scripts/check-card.sh 2.2.6
set -e
cd "$(dirname "$0")/.."
V="$1"; [ -n "$V" ] || { echo "usage: $0 <version>"; exit 1; }
export PATH=/opt/v/bin:/usr/sbin:/sbin:$PATH
W=${OJ_WORK:-/root/ojrel}/sdcheck-$V; rm -rf "$W"; mkdir -p "$W/folder"
truncate -s 8G "$W/card.img"
python3 tools/sdcard/jooki_sd.py new "$W/card.img" --folder "$W/folder" --yes 2>&1 | tail -n 4
echo "--- sgdisk"; sgdisk -v "$W/card.img" 2>&1 | tail -n 2
LOOP=$(losetup -Pf --show "$W/card.img")
trap 'umount /mnt/oj-sd3 2>/dev/null; losetup -d "$LOOP"; rm -rf "$W"' EXIT
for p in 2 3 5 7; do echo "--- e2fsck p$p"; e2fsck -fn "${LOOP}p$p" 2>&1 | tail -n 1; done
mkdir -p /mnt/oj-sd3; mount -o ro "${LOOP}p3" /mnt/oj-sd3
GOT=$(cat /mnt/oj-sd3/etc/openjooki-version 2>/dev/null)
echo "--- version on p3: $GOT"; md5sum /mnt/oj-sd3/jooki/lib/player.lib
umount /mnt/oj-sd3
[ "$GOT" = "$V" ] || { echo "the card is not $V"; exit 1; }
echo "CARD OK: $V"
