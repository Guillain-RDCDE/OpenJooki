#!/bin/ash
# OpenJooki — SAFE A/B self-install, run ON the Jooki (phone path / no-PC path).
# Usage: openjooki-selfupdate.sh <image> [--dry]
#   <image>: firmware already present on the Jooki (raw .img or .img.gz).
#   --dry  : writes + verifies on the spare partition, WITHOUT activating (no reboot).
# Guarantees: NEVER writes to the active partition nor to boot/factory;
# verifies bit for bit (sha256); arms the U-Boot rollback (auto return if it doesn't start).
IMG="$1"; MODE="$2"
log(){ echo "[openjooki] $*"; }
[ -f "$IMG" ] || { log "IMAGE NOT FOUND: $IMG"; exit 2; }

A=$(fw_printenv mender_boot_part 2>/dev/null | sed 's/.*=//')
case "$A" in 2) S=3;; 3) S=2;; *) log "UNEXPECTED ACTIVE PARTITION: $A"; exit 2;; esac
SDEV="/dev/mmcblk0p$S"
grep -q "root=/dev/mmcblk0p$A" /proc/cmdline || { log "SAFETY: active != $A, aborting"; exit 2; }
# p2/p3 sizes identical (safeguard)
P2=$(cat /sys/class/block/mmcblk0p2/size); P3=$(cat /sys/class/block/mmcblk0p3/size)
[ "$P2" = "$P3" ] || { log "SAFETY: p2/p3 sizes differ, aborting"; exit 2; }
umount /mnt/spchk /mnt/p2patch 2>/dev/null

log "reference fingerprint (source)…"
case "$IMG" in
  *.gz) WANT=$(gzip -dc "$IMG" | sha256sum | cut -d' ' -f1)
        TOTAL=$(gzip -dc "$IMG" | wc -c);;
  *)    WANT=$(sha256sum "$IMG" | cut -d' ' -f1)
        TOTAL=$(wc -c < "$IMG");;
esac
PBYTES=$((P2*512))
[ "$TOTAL" -le "$PBYTES" ] || { log "SAFETY: image too large ($TOTAL > $PBYTES)"; exit 2; }

log "writing to spare partition p$S (do not unplug)…"
case "$IMG" in
  *.gz) gzip -dc "$IMG" | dd of="$SDEV" bs=1M 2>/dev/null;;
  *)    dd if="$IMG" of="$SDEV" bs=1M 2>/dev/null;;
esac
sync

log "bit-for-bit verification…"
B=$((TOTAL/512)); R=$((TOTAL%512))
if [ "$R" -gt 0 ]; then
  GOT=$({ dd if="$SDEV" bs=512 count="$B" 2>/dev/null; dd if="$SDEV" bs=1 skip=$((B*512)) count="$R" 2>/dev/null; } | sha256sum | cut -d' ' -f1)
else
  GOT=$(dd if="$SDEV" bs=512 count="$B" 2>/dev/null | sha256sum | cut -d' ' -f1)
fi
[ "$GOT" = "$WANT" ] || { log "VERIFY FAILED ($GOT != $WANT) — nothing activated, Jooki intact"; exit 3; }
log "transfer bit-perfect identical OK"

log "bootable system check…"
mkdir -p /mnt/spchk
mount -o ro "$SDEV" /mnt/spchk 2>/dev/null || { log "image not mountable — nothing activated"; exit 3; }
if [ ! -f /mnt/spchk/boot/uImage ]; then umount /mnt/spchk; log "no kernel — nothing activated"; exit 3; fi
umount /mnt/spchk

if [ "$MODE" = "--dry" ]; then
  log "OK (--dry mode): firmware written and verified on p$S, NOT activated."; exit 0
fi

log "arming U-Boot rollback + activating p$S…"
echo -n 0 > /sys/kernel/htdrv/bootcount 2>/dev/null
fw_setenv bootcount 0
fw_setenv upgrade_available 1
fw_setenv mender_boot_part "$S"
fw_setenv mender_boot_part_hex "$S"
sync
log "REBOOT_NOW: the Jooki reboots onto p$S. If it doesn't start, U-Boot returns on its own to p$A."
reboot
