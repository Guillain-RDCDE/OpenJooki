# OpenJooki Tool

Take back control of your **Jooki v2** from a computer, after Muuselabs shut down
its servers. A simple tool, in readable Python (no dependencies), that talks to the
Jooki on your local network.

## ⛑️ Promise: **this tool cannot brick your Jooki**
- It **never touches** the bootloader or the factory partition.
- It **backs up before** any write.
- System patches go through the **original A/B mechanism** (Mender): the update is
  written to the **spare** partition, then it switches while **arming the U-Boot
  rollback** (`upgrade_available=1`, counter reset). If the new partition **does not
  boot**, U-Boot (`bootlimit=1`) **returns on its own** to the old one — no
  computer, just a power-cycle. When it boots, the trial is **committed**
  automatically.
- The code is **fully readable** (a single file, standard library).

> **Every write command is tested on a real Jooki before release.**
> Music writes only to the content area; system patches go through A/B (spare
> partition + rollback).

## Requirements
- Python 3, and `ssh` (built in on macOS / Linux / Windows 10+).
- The Jooki powered on, on the same Wi-Fi network as the computer.

## Usage
```sh
python3 jooki.py discover              # find the Jooki on the network
python3 jooki.py --host 192.168.1.61 info      # device info
python3 jooki.py --host 192.168.1.61 backup    # backup (system + content)
```
### System patches (A/B, anti-brick)
```sh
python3 jooki.py --host 192.168.1.61 patch status     # active / spare partition
python3 jooki.py --host 192.168.1.61 patch cut-cloud  # cut the cloud heartbeat
python3 jooki.py --host 192.168.1.61 patch harden     # apply the security/robustness audit
python3 jooki.py --host 192.168.1.61 patch switch 2   # roll back to the other partition
```
A patch first clones the **active** partition to the **spare** partition, writes to
it, **arms the U-Boot rollback**, **switches**, then **verifies** and **commits**
the trial; if in doubt it **returns** to the previous state (and even if it loses
the network, U-Boot switches back on its own at power-up). The fixes applied by
`harden` are readable one by one in `patches/`.

Backups go to `~/.openjooki/backups/`. A dedicated SSH key is created in
`~/.openjooki/` (it is only used for this Jooki, on your local network).

## Technical details (for the curious)
- The Jooki is an embedded Linux (Ingenic X1000 SoC, MIPS) + an ESP32 co-processor
  (Wi-Fi/BT/NFC). Everything is driven by an internal MQTT bus.
- Root access is via an **RSA** key (the original SSH server, dropbear, does not
  accept ed25519) on a service started on **port 2222**.
- See the repo's `docs/` folder for the full analysis and design.

## Install a firmware — "zero-effort", Mac / PC / phone
A **local web** interface (reliable rendering everywhere; macOS Tk does not render).
- **Mac**: double-click `OpenJooki Installer.app` (in `tools/openjooki/`).
- **PC / Linux / by hand**: `python3 installer_web.py`.

The browser opens: **drag and drop** the firmware (`.img`, `.ext4`, `.img.gz`),
click **"Install safely"**. A progress bar does everything: write to the **spare**
partition, **bit-perfect verification**, "bootable system" check, then
**activation** and test. If it does not boot, the Jooki **returns on its own** to
the previous version. Nothing can brick it.

**From your phone**: `python3 installer_web.py --lan` prints an address
`http://<mac-ip>:PORT/` to open on the phone (same Wi-Fi) — you drive everything
from the phone. (The "no PC at all" path is in progress, see
`docs/14-installateur-multiplateforme.md`.)

Command line (advanced): `python3 installer.py <firmware>`
(`--no-switch` to write+verify without activating, `--selftest` for a safe test).

> Tip: distribute the firmware as **`.img.gz`** — only the compressed bytes travel
> over the network, and the Jooki decompresses while writing (much faster).

## Status
- [x] `discover`, `info`, `backup` (+`--quick`) — **tested 100% on a real Jooki (J2000)**.
- [x] `playlist list/new`, `music add` — **tested 100%** (upload + MQTT, backup-before-write).
- [ ] `token` (name/associate a token) — same mechanism, to be wired.
- [x] `patch status/clone/switch` — **A/B tested 100%** (verified clone + proven p3↔p2 switch on the device).
- [x] **Automatic rollback locked in** — `switch` arms U-Boot (`upgrade_available`/bootcount) then commits; armed cycle p3→p2→p3 verified 100%.
- [x] `patch cut-cloud` — **cuts the cloud heartbeat, tested 100%** (A/B patch applied on the device, cloud neutralized, rollback available).
- [x] `patch harden` — **security/robustness audit (5 fixes), tested 100%** (A/B applied + verified file by file, idempotent, rollback available).
- [x] **Firmware installer (Mac app + `installer.py`)** — writes to spare, **bit-perfect check**, bootable check, activates with armed rollback. **Tested end-to-end 100%** (real install p3→p2→p3, compressed image decompressed on the device).
- [x] 100% automatic rollback for OS patches (via armed A/B); serial console reserved for patches touching **the boot/kernel** (out of scope).
- [ ] `esp32-flash` — reflash the ESP32 (opt-in, advanced).

## License
MIT.

## Disclaimer
Community project, not affiliated with Muuselabs/Jooki. Use at your own risk; the
tool is designed to be safe, but always keep a backup.
