# OpenJooki installer — cross-platform & "from the phone"

Goal: update the Jooki safely from any device, using the same proven anti-brick
engine (write to the spare partition, bit-perfect verification, A/B activation
with armed U-Boot rollback).

## 1. Desktop — Mac / PC / Linux  ✅ DONE & VERIFIED
`tools/openjooki/installer_web.py`: a small local web server (standard library)
serves a page; you **drag and drop** the firmware into the browser, it is
sent to the server, then installed by `installer.py`. No OS-specific component
(no Tk, no osascript) → **a single codebase everywhere**.
- Rendering verified (Safari): clean page, Jooki detected "online ✓".
- Upload verified: `POST /upload` receives the file, detects the compression,
  computes the decompressed size, arms the install button.
- Real end-to-end install already proven (compressed image → decompression
  on the device → bit-perfect verification → p3→p2 activation → back to p3).
- Launch: `OpenJooki Installer.app` (double-click, macOS) or
  `python3 installer_web.py`. Windows: `python installer_web.py` (Python required;
  a standalone executable (.exe) via PyInstaller is a later step).

## 2. Phone → PC → Jooki (WiFi)  ✅ DONE (`--lan` option)
`python3 installer_web.py --lan` makes the server listen on the local network and
prints an address `http://<mac-ip>:PORT/`. You open it **from the phone**
(same WiFi): you drive the whole install from the mobile, while the computer
does the work. Bluetooth is not used (see §4).

## 3. Phone WITHOUT a PC — the Jooki updates itself  🔬 FEASIBILITY CONFIRMED, to be finalized
Target: from the phone, go to `http://jooki2-0426E8.local/openjooki.html`,
drop the firmware, and **the Jooki installs it on itself**.

What we confirmed on the device:
- The Jooki's web server is **web_ctrl**, built on **Mongoose** (`mg_parse_multipart`),
  which listens on `:80` and serves its pages from **`/jooki/app/www/public/`**
  (a **writable** folder: we can drop `openjooki.html` there).
- Existing reusable endpoints: **`/upload`** (multipart, already used for
  music) to receive the firmware, and **`/ll`** (runs a root command, ~100
  characters max, no pipe) to launch the install.
- The install core **on the device** is written and **validated (ash -n)**:
  `tools/openjooki/device/openjooki-selfupdate.sh` — dd onto the spare partition
  (decompresses the .gz on the fly), **bit-perfect sha256 verification** (exact
  byte reads, without `head -c`, which is missing from busybox), "bootable
  system" check, then **U-Boot rollback arming** (`upgrade_available=1`,
  `bootcount=0`) + switch.
  Its building blocks (dd, sha256sum, fw_setenv, htdrv/bootcount, gzip) are all
  present and already proven separately.
- busybox `nc` is minimal (no `-l`/`-e`) → no nc server; so we go through
  web_ctrl/Mongoose, which avoids any origin issue (page served by the Jooki
  itself = same origin as `/upload` and `/ll`).

Still to do (next milestone): `openjooki.html` (same UI as the desktop) dropped
in `/jooki/app/www/public/`, wiring `/upload` → file on disk → `/ll` launches
`selfupdate.sh`, and progress rendered via a small state file served statically.
Then a real install test from the phone. Watch point: max size accepted by
`/upload` and the storage location to confirm; the "commit" (leaving trial mode)
can be left to the U-Boot watchdog or done afterward.

## 4. Bluetooth — honest verdict  ⛔ not for firmware
The Jooki's BLE (via the ESP32) tops out at a few KB/s to a few tens of KB/s.
Transferring an image (even compressed ~40 MB) would take hours and be fragile.
Bluetooth is fine for **commands/state** ("start the update"), not for the
payload. The right pipe for firmware is **WiFi**.

## Recap
| Path | Status | Transport |
|---|---|---|
| Desktop Mac/PC/Linux (drag & drop) | ✅ done & verified | WiFi (PC→Jooki) |
| Phone drives the PC (`--lan`) | ✅ done | WiFi |
| Phone without a PC (Jooki self-update) | 🔬 feasibility confirmed, core written | WiFi (web_ctrl) |
| Bluetooth for firmware | ⛔ ruled out (too slow) | — |
