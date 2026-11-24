# A Wi-Fi chip firmware on trial, without opening the Jooki

Status, 21/11/2026: tried on our own Jooki (see the end): the way back, rehearsed first, then the
new firmware, accepted by the Jooki itself, sound, knob, tokens and Bluetooth fine. Not yet on a
mesh (ours has none). Offered as a trial in the page, *Settings → Advanced → Wi-Fi with several
access points* (OpenJooki 2.5.10), to the families with a mesh who asked (#51).

## For every Jooki, by itself (2.5.17)

Since OpenJooki 2.5.17 the new firmware is for every Jooki (#51, decision of 24/11/2026): it made
meshes and the Wi-Fi at start work, and the way back is built in. `chip_auto_s` (600 s) after
starting, when the Jooki is online and plays nothing (playing, starting or paused: it looks again
10 minutes later), `services.update` runs `chip_trial` with `op = "auto"`. That action does nothing
while an update or a trial runs, once this package was already taken (a mark per package,
`/data/openjooki/esp32-auto.<8 hex>`, set after the download), and unless the state is `none`, or
`accepted` with `version: older`. So a Jooki whose parent went back (`restored`), or whose trial
failed (`failed-*`, `restore-failed`), is left alone. Otherwise it is the same path as *Try the
new version*: download, `oj-esp32-trial install` with all its checks, restart, judged at the next
start. A Jooki refused by the checks (another chip, no room) is not asked again for the same
package. `chip_auto_s = 0` turns it off. Tested by `test_chip_auto.py` and `update_spec.lua`.

## From the page

The row shows only with a core that has it (`maintenance.chip_trial`). The page says what it is
for and that the Jooki comes back by itself, shows where the trial stands (original version,
trying, new version in use, going back), and offers *Try the new version* (two taps) or *Go back
to the original version*. Both are behind the parent code (`OJ_CHIP_TRY`, `OJ_CHIP_BACK`; v2
`chip.try`, `chip.back`); asking where it stands is not (`OJ_CHIP_STATUS`, `chip.status`).

The core's shell action `chip_trial` does the rest in the background and writes its answer to
`/oj-chip.txt` (`state:`, `step:`, then the lines of the checks), read by the page every 3 s:
trying downloads the package from the GitHub pre-release `esp32-wifi`
(`chip_package_url`), hands it to `oj-esp32-trial install` (which checks its SHA-256 and
everything else), and restarts the Jooki only when the trial is staged; a refusal or a failed
download is said on the page and changes nothing. Going back is `oj-esp32-trial uninstall` and a
restart. Tested by `tools/openjooki/tests/test_chip_page.py` (real core and page, the tool and
the restart as stand-ins, the package from the bench's server).

**A newer package.** Each OpenJooki carries the SHA-256 of one package. When a trial is accepted
with an older one (2.5.10 pinned `494de242…`, 2.5.11 pins `d87df74a…`, which also reads the whole
network list at start), `oj-esp32-trial status` says `version: older`; the page then says a newer
version is ready and offers *Try the new version* next to *Go back*. It is put on trial exactly
like the first one (written at the next start, judged, the original back on any failure). Both
packages stay on the `esp32-wifi` pre-release, so a Jooki still on 2.5.10 keeps working.

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

### Done on 21/11/2026

`check` all ok on our Jooki (2.5.9, its installer identical to the bench's). The way back first,
on its own: `restore` asked, restart: the original firmware written back in 37 s, the chip and the
Wi-Fi back, the flag set again. Then `install` and a restart: the new firmware written in 37 s,
`accepted` by the Jooki about 3 minutes after the Wi-Fi was back; `esp32_cmd get_device_info`
says `app_version=0x020C-oj-volume2`. Sound, knob, tokens and Bluetooth headphones fine. The
page's volume works as before (the original Linux controller does not pass the volume API 2 on).
