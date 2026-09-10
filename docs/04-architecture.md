# Jooki v2 technical architecture (reference)

## Overview
A small **Linux** computer on an **Ingenic X1000 (MIPS XBurst)** SoC on an
8 GB SD card + an **ESP32-WROVER-E** co-processor. Local web server + DNS.
OTA updates via **Mender** (Muuselabs servers dead).

## Processors
- **Linux (brain)**: audio, Wi-Fi, storage, web server, playlist logic.
- **ESP32-WROVER-E (co-proc)**: NFC reading (tokens), LEDs, buttons, battery.
  Firmware `.bin` stored on the Linux side, reflashed at boot if the
  `/data/mode/ESP32_FIRMWARE_LOADED` flag is missing.

## SD card — partitions (mmcblk0)
| Part | Mount point | FS | Role |
|---|---|---|---|
| p1 | - (factory) | ext4 | **factory image** — the original Muuselabs system, kept for recovery |
| p2 | / | ext4 | rootfs **A** (system, active or standby) |
| p3 | / | ext4 | rootfs **B** (system, active or standby) |
| p4 | - | swap | virtual memory |
| p5 | /data | ext4 | Spotify, Mender, **OpenJooki scripts** (`/data/openjooki/`), flags `/data/mode/` |
| p6 | /mnt/config | FAT | logs, `jooki.conf` |
| p7 | /jooki/external | ext4 | **content: playlists, tokens, uploads** |

The system runs on **one** of the two A/B rootfs (p2/p3). An update writes the
**other** slot and switches to it (with armed rollback); the **factory** image
(p1) and the bootloader are never written. `mender_boot_part` (U-Boot env) says
which slot boots.

### Going back to factory (Muuselabs) — reversible
The original Muuselabs firmware stays present: on the **factory** partition (p1),
and on whichever A/B slot OpenJooki hasn't overwritten yet. Two ways back, both
leaving `/data` (music) intact:
- **Switch the A/B slot** to the one that still holds Muuselabs —
  `fw_setenv mender_boot_part 3` (or `2`) + matching `mender_boot_part_hex`, then
  reboot. Fully reversible: switch back the same way. OpenJooki stays on its slot.
- **Boot the factory image** — `fw_setenv factory_reset 1` + reboot (U-Boot then
  boots `mender_factory_part`, here p1). Use with care: a factory reset may clear
  user data.

## Data (content partition, /jooki/)
- `playlists.json` — playlists
- `tokens.json` (+ `.bak`) — NFC token UID → playlist mapping
- `audiocfg.json`, `playstate.json`
- `uploads/` — MP3s (named by token ID)
- `artwork/` — cover art

## Local web server — endpoints
- `/upload` — file upload
- `/config` (read) / `/set_config` (write) — `/mnt/config/jooki.conf`
- `/ll?action=<cmd>` — runs a shell command (backdoor, unauthenticated on LAN)
- `/flags?flag=<x>` — flags (injection possible)
- `/wifi`, `/api/wifi/v1/*` — Wi-Fi config
- Homemade DNS on UDP/53 (resolves everything to the box's IP)
- Web UI served locally (SPA, version 3.5.4)

## Real-time control — MQTT
- Broker on **port 1883** (no auth).
- Inputs: `/j/web/input/DO_PLAY`, etc.; state: `/j/web/output/state` (JSON);
  LED: `/j/led/output/set_raw`.

## OTA / cloud (TO NEUTRALIZE in Phase 1)
- Mender: `/etc/mender/mender.conf` → `https://mender2.muuselabs.com` (dead),
  polls every 120 s.
- Heartbeat: `/jooki/app/services/heartbeat.sh` → `https://my.jooki.rocks/...`
  and **executes as root** any code returned after `## ML_OTA` (SSL disabled).
  Risk of takeover if the domain is bought back.

## Root access
- Place your public SSH key in `authorized_keys` by editing
  `/mnt/config/jooki.conf` (endpoint `/config` → `/set_config`), then
  `ssh root@<ip>`.
- Quick alternative: `/ll?action=<cmd>` (direct shell execution).
- Factory hotspot (ESP32): SSID `mnet2`, password `muuselabs256`.

## Useful flags (/data/mode/)
`ESP32_FIRMWARE_LOADED`, `IN_PRODUCTION`, `FACTORY`, `NO_APP`,
`WIFI_ON/OFF`, `SPOTIFY_ON/OFF`.
