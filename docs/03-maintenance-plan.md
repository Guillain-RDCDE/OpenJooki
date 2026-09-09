# Can we maintain the Jooki COMPLETELY? — Plan

_Short answer: YES, in the sense that matters (full control, complete backups,
the ability to modify/restore every software layer, and independence from the
dead Muuselabs servers). The only layer we "freeze and preserve" instead of
rebuilding is the low-level firmware — and that is not a problem._

## What the Jooki v2 really is (architecture)
It is not a magic sealed box: it's a small Linux computer (most likely a
Raspberry Pi Compute Module 3) + an ESP32 microcontroller, both fully
accessible.

- **Brain: Linux** on an 8 GB SD card, ext4, with TWO A/B rootfs (redundancy,
  like a proper atomic-update system).
- **Co-processor: ESP32-WROVER-E** — handles NFC reading (tokens), LEDs,
  buttons, battery. Its firmware (.bin) is stored on the Linux side and
  reflashed at boot if the `ESP32_FIRMWARE_LOADED` flag is missing.
- **Local web server**: exposes /upload, /config, /set_config, /ll, /flags,
  /wifi. Also serves a homemade DNS (UDP/53) and the web app (SPA, Web UI 3.5.4).
- **Updates (OTA)**: a **Mender** client that polls
  `mender2.muuselabs.com` (DEAD). Built-in A/B rollback.

### SD card partitions (mmcblk0)
| Role | Contents |
|---|---|
| factory | base Linux |
| rootfs A / rootfs B | system (redundancy) |
| data (p5) | Spotify, Mender, flags (/data/mode/) |
| config (p6, FAT) | logs, `/mnt/config/jooki.conf` |
| content (p7) | **your data**: playlists, tokens, uploads |

### Where YOUR data is (content partition, /jooki/)
- `/jooki/playlists.json` — playlists
- `/jooki/tokens.json` (+ .bak) — NFC token (UID) → playlist mapping
- `/jooki/audiocfg.json`, `/jooki/playstate.json`
- `/jooki/uploads/` — the MP3s (named by token ID)
- `/jooki/artwork/` — cover art

## What we CAN maintain (and how)
| Layer | Maintainable? | How |
|---|---|---|
| Playlists | YES, fully | web interface, or edit playlists.json as root |
| NFC tokens | YES, fully | tokens.json + JookiTagCreator + NFC reader |
| Upload page / web UI | YES, fully | documented /upload endpoint; we can back up, patch and rehost the SPA |
| Config / network | YES, fully | /config, /set_config, or over SSH |
| Linux OS ("BIOS") | YES to modify, NO to rebuild-from-source | root SSH = we can modify any file/service; dd image = restore/clone. No recompilation from source (closed) |
| ESP32 firmware | Preserve | back up the .bin, reflash the existing one; no sources |

## What we CANNOT do (being honest)
- Recompile the proprietary Linux firmware or the ESP32 firmware from the
  original sources (never published, build system gone). **But unnecessary**:
  root = we can modify everything that runs, and the backup preserves the
  binaries.
- Receive official OTAs (servers dead) — and in any case we want to freeze a
  known-good version.

## THE real long-term danger (worth knowing)
1. **The SD card** dying (years of wear) → hence the importance of a dd image.
2. **Cloud security**: the script `/jooki/app/services/heartbeat.sh` contacts
   `my.jooki.rocks` and EXECUTES as root any code it returns (prefix
   `## ML_OTA`), with SSL disabled. The domain is dead today, but if someone
   buys it back they take root control of the box. Same with Mender. → to be
   neutralized.

## THE PLAN (in phases)

### Phase 0 — Get in + back EVERYTHING up (top priority, do this first)
1. Static IP for A8:EE:C6:04:26:E8 in the router; bookmark jooki2-0426E8.local.
2. Root: add your public SSH key via /config → `ssh root@192.168.1.61`.
3. Full backup: a `dd` image of the SD card (over the network) OR at minimum an
   archive of content + config + data + ESP32 firmware (.bin) + web UI bundle +
   the .json files. → stored in this Jooki folder / Dropbox.
   >>> On its own, this phase gives us the ability to restore everything = the
   foundation of "maintaining completely".

### Phase 1 — Cut the dangerous cloud cords (independence + security)
- Disable heartbeat.sh (the RCE-via-DNS risk) and the Mender poll.
- The box never phones home again, no longer hijackable, 100% local.

### Phase 2 — Own day-to-day management (a "Jooki" repo of our own)
- Upload tool: push a folder of MP3s → /upload + update playlists.json.
- Token manager: NFC UID → playlist, tag generation.
- Regular backup script (JSON + uploads).
- Option: patched web UI (fix jooki.local, features) rehosted.
- Option: MQTT control (port 1883) for home automation / Home Assistant.

### Phase 3 (advanced, optional) — Future-proof the hardware
- Clone the dd image onto a fresh SD card when the original wears out.
- Keep a spare image: if the hardware dies, data+config are portable.

## Verdict
We go from "scattered pieces" to "we own the machine". The low-level firmware,
we back up and freeze (we don't rewrite it — no need). Everything else —
playlists, tokens, upload, web UI, network, services — is entirely under our
control via root. That is real, complete maintenance.

Next concrete action: Phase 0 (root + full backup).
