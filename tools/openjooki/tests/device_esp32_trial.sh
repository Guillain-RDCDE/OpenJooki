#!/bin/bash
# oj-esp32-trial inside the Jooki's own system (docs/32): its busybox, python3.8, esptool 3.0 and
# ml-esp32-install-firmware.sh, under qemu-mipsel (binfmt with the F flag). Only esptool.py is a
# stand-in (esptool_standin.py) that writes the chip's flash into /flash.bin; the real one is only
# asked to parse the new package's arguments. Needs root, a Linux bench, an OpenJooki system image
# and the new package (tools/firmware/package.py). Not in CI (no image there).
#   sudo OJ_ROOTFS=rootfs.img OJ_CANDIDATE=candidate.tgz bash device_esp32_trial.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../../.." && pwd)
IMG=${OJ_ROOTFS:?an OpenJooki rootfs image}; CAND=$(realpath "${OJ_CANDIDATE:?the new firmware package}")
W=${OJ_WORK:-/var/tmp/ojdev}; R=$W/root
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "PASS $*"; }
umount -R $R 2>/dev/null || true
rm -rf $W/rw.img; mkdir -p $R
cp $IMG $W/rw.img; mount -o loop $W/rw.img $R
mount -t proc proc $R/proc
trap 'umount -R $R 2>/dev/null; umount $R 2>/dev/null' EXIT
STOCK=$W/stock.tgz; cp $R/etc/esp32/factory_default_firmware.tgz $STOCK
install -m 755 $REPO/tools/openjooki/system/oj-esp32-trial.sh $R/jooki/bin/oj-esp32-trial
cp $R/usr/bin/esptool.py $W/esptool-real.py
install -m 755 $HERE/esptool_standin.py $R/usr/bin/esptool.py
# never the real reboot: under qemu-user it would restart this machine
rm -f $R/sbin/reboot $R/bin/reboot; printf '#!/bin/ash\ndate > /rebooted\n' > $R/sbin/reboot; chmod 755 $R/sbin/reboot
cp $CAND $R/tmp/candidate.tgz
mkdir -p $R/sys/kernel/htdrv $R/sys/kernel/esp32sdio $R/data/mode $R/data/openjooki
: > $R/dev/ttyS0
for f in esp_reset esp_bootmode; do : > $R/sys/kernel/htdrv/$f; done
echo 524 > $R/sys/kernel/esp32sdio/fw_version
: > $R/data/mode/ESP32_FIRMWARE_LOADED
printf 'Iface\tDestination\tGateway\nethsta0\t00000000\t0101A8C0\t0003\n' > $R/tmp/route
# the chip's flash: 0xFF, and recognisable bytes in the settings (NVS 0x9000-0xd000, the Wi-Fi networks)
python3 - <<PY
f = open("$R/flash.bin", "wb"); f.write(b"\xff" * 0x1000000); f.seek(0x9000); f.write(b"NVS-WIFI" * (0x4000 // 8)); f.close()
PY
cp $R/flash.bin $W/flash.before
J() { chroot $R /usr/bin/env -i PATH=/sbin:/usr/sbin:/bin:/usr/bin OJ_ESP_ROUTES=/tmp/route OJ_ESP_WIFI_S=4 OJ_ESP_STABLE_S=2 OJ_ESP_STEP=1 /bin/ash /jooki/bin/oj-esp32-trial "$@"; }
region() { python3 -c "import sys;f=open(sys.argv[1],'rb');f.seek(int(sys.argv[2],0));print(f.read(int(sys.argv[3],0)).hex())" "$@"; }
same_as_pkg() {  # $1 package: every region of its flash.sh is in /flash.bin
  d=$(mktemp -d); tar xzf $1 -C $d
  for pair in "0x1000 bootloader/bootloader.bin" "0x8000 partition_table/partition-table.bin" "0xd000 ota_data_initial.bin" "0x10000 jooki_v2.bin"; do
    set -- $pair; n=$(stat -c %s $d/esp32/$2)
    [ "$(region $R/flash.bin $1 $n)" = "$(xxd -p $d/esp32/$2 | tr -d '\n')" ] || { rm -rf $d; return 1; }
  done; rm -rf $d
}
nvs_kept() { a=$(region $R/flash.bin 0x9000 0x4000); [ ${#a} -eq 32768 ] && [ "$a" = "$(region $W/flash.before 0x9000 0x4000)" ]; }

echo "--- the Jooki's own tools"
for a in sha256sum tar cut head tail grep awk df mv cp sync logger date sleep; do
  chroot $R /bin/busybox $a --help >/dev/null 2>&1 || chroot $R /bin/busybox sh -c "command -v $a" >/dev/null || fail "no $a on the Jooki"
done
pass "every tool the script uses exists on the Jooki"
chroot $R /bin/ash -n /jooki/bin/oj-esp32-trial || fail "syntax"
pass "the Jooki's ash reads the script"
# the real esptool 3.0 of the Jooki accepts the new package's arguments (it stops at the serial port)
d=$(mktemp -d); tar xzf $CAND -C $d
cp $W/esptool-real.py $R/tmp/esptool-real.py; cp -r $d/esp32 $R/tmp/cand-esp32
args=$(sed -n 's/.*write_flash //p' $d/esp32/flash.sh)
out=$(chroot $R /bin/sh -c "cd /tmp/cand-esp32 && /usr/bin/python3 /tmp/esptool-real.py -p /dev/nonexistent -b 1500000 write_flash $args" 2>&1 || true)
echo "$out" | grep -q "could not open port\|No such file or directory: '/dev/nonexistent'\|Could not open /dev/nonexistent" || fail "real esptool: $out"
echo "$out" | grep -qi "error: argument\|unrecognized\|invalid" && fail "real esptool refused the arguments: $out"
pass "the Jooki's real esptool 3.0 accepts the new package's write (stops only at the missing port)"

echo "--- check and install"
J check /tmp/candidate.tgz || fail "check"
pass "check passes on the Jooki's system"
J install /tmp/candidate.tgz >/dev/null || fail "install"
[ "$(cat $R/data/openjooki/esp32/state)" = staged ] || fail "not staged"
cmp -s $R/flash.bin $W/flash.before || fail "install wrote the chip"
pass "install: staged, the chip untouched"

echo "--- the start writes the new firmware"
J boot
[ "$(cat $R/data/openjooki/esp32/state)" = trying ] || fail "state $(cat $R/data/openjooki/esp32/state)"
same_as_pkg $CAND || fail "the chip does not hold the new firmware"
nvs_kept || fail "the Wi-Fi settings were touched"
[ ! -e $R/data/mode/ESP32_FIRMWARE_LOADED ] || fail "flag still there"
[ "$(cat $R/sys/kernel/htdrv/esp_bootmode)" = 0 ] && [ "$(cat $R/sys/kernel/htdrv/esp_reset)" = 1 ] || fail "chip not back in normal mode"
pass "the Jooki's installer wrote all four regions of the new firmware, the Wi-Fi settings untouched, chip in normal mode"
for i in $(seq 1 20); do [ "$(cat $R/data/openjooki/esp32/state)" = accepted ] && break; sleep 0.5; done
[ "$(cat $R/data/openjooki/esp32/state)" = accepted ] || fail "not accepted: $(cat $R/data/openjooki/esp32/state)"
pass "accepted after the Wi-Fi held (watch running under the Jooki's busybox)"

echo "--- back to the original"
J uninstall >/dev/null; : > $R/data/mode/ESP32_FIRMWARE_LOADED
J boot
[ "$(cat $R/data/openjooki/esp32/state)" = restored ] || fail "state $(cat $R/data/openjooki/esp32/state)"
same_as_pkg $STOCK || fail "the chip does not hold the original firmware"
nvs_kept || fail "the Wi-Fi settings were touched"
pass "the original firmware is back, byte for byte in all four regions, the Wi-Fi settings untouched"

echo "--- not accepted: no Wi-Fi"
: > $R/data/mode/ESP32_FIRMWARE_LOADED; rm -f $R/data/openjooki/esp32/state
J install /tmp/candidate.tgz >/dev/null || fail "install 2"
printf 'Iface\tDestination\n' > $R/tmp/route
J boot
same_as_pkg $CAND || fail "new firmware not written"
for i in $(seq 1 30); do [ "$(cat $R/data/openjooki/esp32/state)" = restore ] && break; sleep 0.5; done
[ "$(cat $R/data/openjooki/esp32/state)" = restore ] || fail "no verdict: $(cat $R/data/openjooki/esp32/state)"
for i in $(seq 1 20); do [ -e $R/rebooted ] && break; sleep 0.5; done
[ -e $R/rebooted ] || { ls -la $R/sbin/reboot; cat $R/sbin/reboot; cat $R/data/openjooki/esp32/log; fail "no restart asked"; }
J boot
[ "$(cat $R/data/openjooki/esp32/state)" = restored ] && same_as_pkg $STOCK && nvs_kept || fail "not restored"
pass "no Wi-Fi: restart asked, then the original firmware back, byte for byte"

echo "--- the whole start script (S55) with the trial in it"
install -m 755 $REPO/tools/openjooki/system/S55_ml-start-wifi.sh $R/etc/rcS.d/S55_ml-start-wifi.sh
# the hardware S55 talks to: the chip's driver and its command tool are stand-ins that log
for t in /sbin/modprobe /usr/bin/cgexec; do rm -f $R$t; printf '#!/bin/ash\necho "%s $*" >> /hw.log\n' $t > $R$t; chmod 755 $R$t; done
mv $R/jooki/bin/esp32_cmd $W/esp32_cmd.real 2>/dev/null || true
printf '#!/bin/ash\necho "esp32_cmd $*" >> /hw.log\n[ "$1" = get_airplane_mode ] && echo disabled\nexit 0\n' > $R/jooki/bin/esp32_cmd; chmod 755 $R/jooki/bin/esp32_cmd
mkdir -p $R/sys/kernel/debug/mmc1 "$R/sys/bus/sdio/devices/mmc1:0001:2" $R/mnt/config
echo 50000000 > $R/sys/kernel/debug/mmc1/clock; echo 516 > $R/sys/kernel/esp32sdio/api_version
echo a8:ee:c6:00:00:01 > $R/sys/kernel/htdrv/mac
printf 'Iface\tDestination\nethsta0\t00000000\t0101A8C0\t0003\n' > $R/tmp/route
S55() { rm -f $R/hw.log; chroot $R /usr/bin/env -i PATH=/sbin:/usr/sbin:/bin:/usr/bin OJ_ESP_ROUTES=/tmp/route OJ_ESP_WIFI_S=4 OJ_ESP_STABLE_S=2 OJ_ESP_STEP=1 /bin/ash -c '. /etc/rcS.d/S55_ml-start-wifi.sh' > $W/s55.out 2>&1 || true; }
: > $R/data/mode/ESP32_FIRMWARE_LOADED; rm -f $R/data/openjooki/esp32/state $R/esptool.log
S55
[ ! -e $R/esptool.log ] && [ -e $R/data/mode/ESP32_FIRMWARE_LOADED ] && grep -q "esp32_cmd get_airplane_mode" $R/hw.log || { cat $W/s55.out; fail "S55 without a trial"; }
pass "S55 without a trial: the chip is not written, the start goes to its end"
J install /tmp/candidate.tgz >/dev/null || fail "install 3"
S55
same_as_pkg $CAND || { cat $W/s55.out; fail "S55 did not write the new firmware"; }
grep -q "esp32_cmd set_mac_addr 127 a8:ee:c6:00:00:01" $R/hw.log && grep -q "/sbin/modprobe esp32sdio" $R/hw.log || { cat $R/hw.log; fail "S55 did not start the chip as after a factory write"; }
[ -e $R/data/mode/ESP32_FIRMWARE_LOADED ] && grep -q "esp32_cmd get_airplane_mode" $R/hw.log || { cat $W/s55.out; fail "S55 stopped early"; }
pass "S55 writes the new firmware, then starts the chip as after a factory write (driver, MAC address, flag) and goes to its end"
for i in $(seq 1 20); do [ "$(cat $R/data/openjooki/esp32/state)" = accepted ] && break; sleep 0.5; done
[ "$(cat $R/data/openjooki/esp32/state)" = accepted ] || fail "not accepted after S55: $(cat $R/data/openjooki/esp32/state)"
pass "accepted after a real S55"
rm -f $R/esptool.log; S55
[ ! -e $R/esptool.log ] || fail "an accepted trial is written again"
pass "the next start leaves the accepted firmware alone"
J uninstall >/dev/null; S55
[ "$(cat $R/data/openjooki/esp32/state)" = restored ] && same_as_pkg $STOCK && nvs_kept && [ -e $R/data/mode/ESP32_FIRMWARE_LOADED ] || { cat $W/s55.out; fail "S55 did not bring the original back"; }
pass "uninstall: S55 writes the original back, the Wi-Fi settings untouched, and starts the chip"
echo "--- esptool calls"; cat $R/esptool.log | cut -c1-160
echo ALL-OK
