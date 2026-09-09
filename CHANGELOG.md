# OpenJooki — Changelog

## v0.2.1 (2026-09-09) — cross-platform (web) installer + "phone" groundwork
- **Local web installer** (`installer_web.py`) replacing the Tk GUI (macOS Tk does
  not render): page served locally, firmware **drag-and-drop**, progress bar,
  reliable rendering everywhere. **Mac / PC / Linux, one codebase.** Rendering
  verified (Safari) and upload (`/upload`) verified server-side.
- **`--lan`**: the server listens on the local network → you can **drive the
  install from your phone** (the computer does the work).
- **Optimized transfer** kept: a `.gz` image is sent compressed and decompressed on
  the device (~15× lighter on the network).
- **On-device self-install core**: `device/openjooki-selfupdate.sh` (validated with
  `ash -n`) — for the upcoming "phone, no PC" path via the Jooki's internal web
  server (web_ctrl/Mongoose, doc root `/jooki/app/www/public/`).
- Docs: `docs/14-cross-platform-installer.md` (status, feasibility, Bluetooth
  verdict: not suitable for firmware).

## v0.2.0 (2026-09-09) — "zero-effort" graphical installer
A real double-clickable Mac app to install a firmware **with no technical
knowledge**, with all the proven anti-brick protections.
- **OpenJooki Installer.app** (Tkinter, no dependencies): choose a firmware file,
  click, a progress bar does the rest. Clear result ("Done, your Jooki is running"
  / "automatic return to the previous version").
- **`installer.py` engine** — end-to-end safety:
  * writes only to the **spare** partition (never the active one or the boot);
  * **bit-perfect verification** (SHA-256 read back from the partition == source) —
    exact byte read via `dd` (this busybox has no `head -c`);
  * checks the image is a **bootable system** before activating;
  * **activation** via A/B with **armed U-Boot rollback** (auto return if it does
    not boot);
  * cleanly refuses (without activating anything) an image that is too big, too
    small, or not bootable.
- **Optimized transfer**: a compressed image (.gz) only sends the compressed bytes;
  **the Jooki decompresses** while writing (~15× lighter on the network).
- Verified 100% on the device: bit-perfect self-test (source hash = file =
  exact byte region); real end-to-end install of a real image (compressed transfer
  → bit-perfect check → activation p3→p2 → return to p3), Jooki intact.

## v0.1.2 (2026-09-09) — automatic rollback locked in
- `patch switch` (and therefore `cut-cloud`/`harden`) now **arms the U-Boot
  rollback** before each switch, exactly like a real Mender update: boot counter
  reset (`htdrv/bootcount` + env), trial boot (`upgrade_available=1`). If the new
  partition **does not boot**, U-Boot (`bootlimit=1`, `mender_altbootcmd`)
  **returns on its own** to the other partition — no computer, just a power-cycle.
- **Commit** automatically when the partition boots correctly
  (`upgrade_available=0` + `ht_reset_bootcount.sh`): no "pending" state lingers
  after a successful switch.
- Verified 100% on the device: armed cycle p3→p2→p3, `upgrade_available` flag going
  to 1 (armed) then 0 (committed) at each step, Jooki back to identical.

## v0.1.1 (2026-09-09) — security + robustness audit
Fixes from a professional audit of the existing firmware, applied and
**verified 100% on the device** (A/B partition, rollback preserved).
- New command `patch harden`: applies the fixes from the `patches/` folder via the
  A/B mechanism (clone → write to the copy → switch → per-file verification),
  **idempotent** ("already applied" when there is nothing to do) and **anti-brick**
  (automatic rollback if a file diverges, the spare partition is always unmounted
  even on failure).
- 5 fixes, delivered as **auditable** files in `patches/`:
  - `ble.sh` — neutralizes two backdoors (arbitrary code execution via the `u)`
    userset and `_)` custom cases); the legitimate functions are kept.
  - `run_rpc_cmd.sh` — refuses remote command execution (removes a TOCTOU
    "verify then execute" flaw).
  - `check_online.sh` — removes the infinite ping loop to the dead server.
  - `is_mounted.sh` — anchored mount test (`grep -qF " $1 "`), no more false
    positives.
  - `wait_for_file.sh` — adds a timeout (no more infinite wait).
- Fixed: `patches/ble.sh` contained an erroneous double backslash
  (`grep 'SSID\\|Not'`); realigned byte-for-byte with the verified version running
  on the device (`grep 'SSID\|Not'`).
- Reliability: file transfer via `cat`/heredoc (this busybox has no `base64`
  applet).

## v0.1.0 (2026-09-09) — first version
Safely taking back control of a Jooki v2 after the Muuselabs servers shut down.
- `openjooki` CLI tool (Python, no dependencies):
  - `discover`, `info`, `backup` (+`--quick`) — tested on a real Jooki.
  - `playlist list/new`, `music add` — re-adding music (upload + MQTT).
  - `patch status/clone/switch` — A/B firmware patch (clone + switch, proven).
  - `patch cut-cloud` — cuts the cloud heartbeat (phone-home + `## ML_OTA`
    backdoor), applied and verified on the device, with rollback.
- Full firmware analysis (docs/): architecture, MQTT bus, ESP32 protocol,
  content API, anti-brick A/B mechanism.
- Anti-brick promise: never touches bootloader/factory partition, backs up before
  writing, OS patches via A/B with rollback.
