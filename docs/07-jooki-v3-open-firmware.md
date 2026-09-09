# Jooki v3 — open source firmware: feasibility & roadmap

## Verdict
**Yes, it's feasible.** The Jooki v2 is a standard embedded Linux computer
(Ingenic X1000 SoC, MIPS) that **boots from a removable SD card**. That detail
is decisive: we develop on a spare SD, test on the real Jooki, and if it doesn't
boot we put the original SD back → **zero risk of bricking**. We already have
root + backups, i.e. half the journey (extraction / understanding).

## Two philosophies — and the right strategy
- **Path A — open userspace on the original base**: we KEEP the Muuselabs
  kernel/bootloader, disable the stock app, and run OUR services (audio player
  + web app + NFC bridge) on top. ~80% of the benefit (maintainable, new
  features, zero cloud) for ~20% of the effort, no kernel work. Fast, safe.
- **Path B — fully open firmware (the real "v3")**: we rebuild everything
  (bootloader + kernel + rootfs) with Buildroot/Yocto, our own OTA. Total
  ownership, maximum effort.
- **Recommendation: start with A**, because the open app is **reusable as-is**
  on Path B. We migrate the base underneath later. Nothing is thrown away.

## Anatomy of the Jooki v2 (keep / rewrite)
| Layer | Detail | Verdict |
|---|---|---|
| Bootloader | U-Boot (X1000) + fw_env | keep at first (open available) |
| Kernel | Linux 5.7 + X1000 device tree | keep at first; extract .config/DTB |
| Rootfs | BusyBox (Yocto-style build) | keep (A) / rebuild with Buildroot (B) |
| Audio | GStreamer (gstregistry.bin) | replace with **MPD** (simple, robust) |
| ESP32 co-proc | NFC + LED + buttons + battery, over serial | reverse the protocol; stock firmware as a black box |
| Web + API | home-grown server (/ll,/config,/upload) + MQTT | **rewrite** (our new features) |
| OTA | mender, A/B | keep mender (open) or simplify (swupdate/rauc) |
| Cloud/heartbeat | my.jooki.rocks | **remove** |

## The key unknown: the ESP32
The Jooki's one truly unique piece is the **Linux ↔ ESP32** dialogue. You place
a token → the ESP32 reads the NFC UID and sends it to Linux (probably over a
serial port `/dev/ttyS*`) → Linux plays the associated playlist; conversely,
Linux drives the LEDs. **We need to sniff this protocol** (listen on the serial
line while placing tokens / pressing buttons). Once understood, everything else
is standard Linux. We **keep the original ESP32 firmware** (backed up) and speak
its protocol; rewriting it (ESP-IDF) is a later bonus.

## Milestone roadmap
- **M0 — Extraction & understanding (≈ done)**: root ✅, data backups ✅.
  Remaining: full disk image, dump of bootloader/kernel/DTB/.config, ESP32
  firmware, mapping of services & init.
- **M1 — Safe dev loop**: spare SD → clone the image onto it → **boot the CLONE**
  on the Jooki. Proves we can boot OUR card (anti-brick safety net).
- **M2 — ESP32 protocol**: sniff the serial line, document UID→event and the
  LED/button/battery commands. Write a small `jooki-esp-bridge`.
- **M3 — Open app (Path A) on the stock base**: disable the Muuselabs app, run
  **MPD + our web app** (playlists, upload, tokens, device info) + the ESP32
  bridge. → A fully usable, maintained, cloud-free Jooki. **Already a working
  "v3."**
- **M4 — Open base (Path B)**: Buildroot for X1000 (extracted kernel+DTB),
  minimal rootfs booting from SD, then drop the M3 app on top. Clean OTA (A/B).
- **M5 — Bonus**: open ESP32 firmware, new features (better playlists,
  stories/TTS, home-automation integration, multi-room, finer parental
  controls…).

## Risks — honestly
- **Easy (high confidence)**: web/API app, MPD, NFC bridge, cloud removal,
  backups/OTA. Pure Linux.
- **Medium**: Buildroot X1000 bring-up (kernel+DTB+U-Boot). De-risked by:
  Ingenic-community sources, replicating the existing .config/DTB, and the
  **removable SD boot** (risk-free testing).
- **Specialized**: device tree / drivers (I2S codec, LED, battery gauge) — but
  we have them as binary/config on the image, so they're reproducible.
- **Hardware**: no risk as long as we don't touch the NAND/SPI bootloader —
  we boot from SD and keep the original SD intact.

## Hardware needed
- 1 microSD reader + 1 **spare SD card** (≥ 8 GB) → clone and experiment
  without touching the original. *(essential)*
- (Optional) a **3.3 V USB-serial** adapter → U-Boot/kernel console for debug.
- (Optional, later) what's needed to flash the ESP32 if rewriting.

## Community leverage
- **Ingenic-community/linux** (kernel), Buildroot/OpenWrt Ingenic topics.
- rclancey/jooki (Go client), ha-jooki (MQTT protocol), nv1t (reverse
  engineering), SveLil/JookiTagCreator (NFC).
- Our repo would become the first **cleanly packaged "OpenJooki"** — nobody has
  done it.

## Concrete next action
Finish the **disk image** (gold), then **M1** (spare SD + cloning = dev loop).
In parallel, **M2** (ESP32 sniff) is already doable with root access.
