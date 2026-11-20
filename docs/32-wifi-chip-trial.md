# A Wi-Fi chip firmware on trial, without opening the Jooki

Status, 20/11/2026: ready for a first trial on our own Jooki. Never run on a real Jooki yet.
Families are not offered it (decision of 08/11/2026); a page button comes only after that trial.

The new firmware is the chip fix for mesh networks (docs/20, `tools/firmware/wifi-roaming.patch`,
on top of the volume firmware of docs/30-31). This page is about putting it on a Jooki and taking
it off again, by the Jooki itself.

## Why the Jooki can do it alone

- **It already writes its chip.** At every start, the original start script (S55) writes the
  original firmware when the "firmware loaded" flag is missing, or when the chip reports another
  API than the system expects: `/usr/bin/ml-esp32-install-firmware.sh` puts the chip in download
  mode (`/sys/kernel/htdrv/esp_bootmode`, `esp_reset`) and runs the package's `flash.sh`, that is
  the Jooki's own `esptool.py` 3.0 over its internal serial line (`/dev/ttyS0`). Nothing is opened.
- **The chip can always be written again.** Download mode is in the chip's ROM: a half-written or
  broken firmware does not prevent the next write, as long as Linux starts (it does not need the
  chip to start).
- **The original stays on the Jooki**: `/etc/esp32/factory_default_firmware.tgz` (SHA-256
  `7af7a71f…2ed8c53` on the Jookis checked), plus a checked copy on `/data`.
- **The Wi-Fi networks stay.** Both packages write the same four regions: bootloader (0x1000),
  partition table (0x8000), OTA data (0xd000), application (0x10000). The chip's settings (NVS,
  0x9000-0xd000, where the networks are) are never written. The two partition tables are
  identical byte for byte.

## How it works (`oj-esp32-trial`, called by S55)

```
oj-esp32-trial check <package>     read-only: is this Jooki ready for that package?
oj-esp32-trial install <package>   check, keep both packages on /data; written at the next start
oj-esp32-trial uninstall           back to the original firmware at the next start
oj-esp32-trial status              where the trial stands, and its log
```

- `install` writes nothing to the chip. It refuses unless every line of `check` is ok: the package
  is exactly the expected one (SHA-256 pinned in the script), the original package is the one this
  was checked against, the system expects chip API 0x0204 (the new firmware keeps it, so S55 never
  rewrites the original over it), the chip answers and the Wi-Fi works now (the trial is judged on
  it), and there is room on `/data`.
- At the next start, S55 calls `oj-esp32-trial boot` right after its own factory write and before
  the chip's logger and driver are used: the new firmware is written with the Jooki's installer,
  then S55 starts the chip as after a factory write (driver, MAC address, flag).
- **Judged**: within 10 minutes the chip must answer and the Wi-Fi must give Linux a route, and
  both must still hold 2 minutes later. Then the trial is `accepted` and later starts leave it alone.
- **Back by itself**, at the start (before anything uses the chip), with the same installer and the
  original package, whenever:
  - the write failed (tried again at once),
  - the Jooki stopped in the middle of the write (power, battery),
  - the verdict was "no" (no Wi-Fi, a chip that does not answer, a Wi-Fi that does not hold; the
    Jooki then restarts by itself),
  - the Jooki restarted before the verdict,
  - someone asked (`uninstall`).
  A write back that fails is tried twice per start, at three starts; after that it stops and says
  so (`restore-failed`), leaving the chip in normal mode. Only then would opening the Jooki help.
- Logged in `/data/openjooki/esp32/log` and the system log (`oj-esp32`).

## Tested

- `tools/openjooki/tests/test_esp32_trial.py` (60 checks, busybox ash, stand-ins for the
  installer, df, reboot): every condition of `check`, the good path, each way back above, damaged
  packages, a write back failing three starts, uninstall at every stage, the hook's place in S55.
  Passed three runs in a row.
- `tools/openjooki/tests/device_esp32_trial.sh` (root, Linux bench, not CI): the same script
  **inside the Jooki's own system** (2.4.1 image under qemu-mipsel: its busybox, python 3.8,
  `ml-esp32-install-firmware.sh`, and the whole real S55), with only `esptool.py` replaced by a
  stand-in writing a 16 MiB flash file. Checked: every tool exists on the Jooki; the Jooki's real
  esptool 3.0 accepts the new package's arguments; the new firmware and then the original land
  byte for byte in all four regions; the Wi-Fi settings region is never touched; the chip is left in
  normal mode; S55 runs to its end, writes the MAC address and the flag again.
- The packages: `tools/firmware/package.py` builds the new one reproducibly (twice, same bytes,
  SHA-256 `494de242…f2a5a`), `package.py check` passes on both.

**Not tested**: a real chip. The real esptool talking to a real chip, the new firmware starting on
it, the Wi-Fi and roaming on a mesh. The ESP32 emulator (Espressif's QEMU) could not be used on
the bench. That is what the trial on our Jooki is for.

## The trial on our Jooki

On the charger, on the Wi-Fi, OpenJooki with this script (2.5.8 or later), maintenance SSH open.

1. Copy the package: `build/firmware/openjooki-esp32-494de242.tgz` → `/data/openjooki/candidate.tgz`.
2. `oj-esp32-trial check /data/openjooki/candidate.tgz`: every line `ok`.
3. `oj-esp32-trial install /data/openjooki/candidate.tgz`, then restart the Jooki.
4. About 2 minutes later (the start is about a minute longer): `oj-esp32-trial status`
   says `trying`, then `accepted` about 3 minutes after the Wi-Fi is back.
5. Check: sound on the speaker, the knob, tokens, Bluetooth headphones, the page's volume.
   Then the mesh: move the Jooki between access points and watch `Roaming from` in
   the system log (`/mnt/config/log/jooki-<day>.log`, the chip's lines are copied there).
6. Back to the original at any time: `oj-esp32-trial uninstall`, then restart.

If the Jooki ends with no Wi-Fi and no sound after all that (`restore-failed`): open it and
restore over the serial line (docs/31, recovery).
