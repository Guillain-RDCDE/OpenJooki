# OpenJooki

Take back control of a **Jooki v2** after Muuselabs shut down its servers, and
maintain it yourself: backup, re-adding music, security fixes, and **safe
updates** — all without ever being able to brick it.

> Independent community project, not affiliated with Muuselabs / Jooki.
> The Jooki stays your device; you simply regain control of it.

## What it is

The Jooki is a kids' music player (embedded Linux + an ESP32 co-processor). With
its servers gone, OpenJooki provides **open, readable** tools to keep using it and
improve it:

- **`openjooki`** — a command-line tool (Python, no dependencies): network
  discovery, backup, re-adding playlists / music.
- **"Zero-effort" installer** — a local web interface (Mac / PC / mobile): drag and
  drop a firmware, a progress bar does the rest.
- **Auditable security fixes** (backdoors neutralized, dead cloud cut off) applied
  through the original A/B mechanism.
- **Updates from this repository** — the Jooki can fetch the latest published
  version here and install it by itself, over Wi-Fi.

## The promise: it cannot brick your Jooki

Every write goes through the original **A/B** mechanism (Mender):

1. the update is written to the **spare** partition, never the running one;
2. the transfer is **verified bit-for-bit** (sha256);
3. activation **arms the U-Boot rollback** — if the new version does not boot, the
   device **returns on its own** to the previous one at the next power-up.

The bootloader and the factory partition are **never** touched.

## Updating from GitHub

Each published version is a **release** containing `openjooki-firmware-X.Y.Z.img.gz`
and a `version.json` (version number + `sha256`). On the Jooki, `openjooki-ota.sh`
fetches the manifest, compares versions, downloads over HTTPS, **checks the sha256**,
then installs via A/B. An incomplete or corrupted image is rejected, and the
rollback prevents any brick regardless. See `docs/14` and `docs/15`.

## Layout

- `tools/openjooki/` — the tool, the web installer, the auditable fixes.
- `tools/openjooki/device/` — scripts run on the Jooki (self-install, OTA).
- `docs/` — technical analysis, architecture, runbooks, audit, maintenance plan.
- `scripts/` — utilities (preparing a release).

## Quick start

```sh
# find the Jooki and back it up
python3 tools/openjooki/jooki.py discover
python3 tools/openjooki/jooki.py --host 192.168.1.61 backup

# install a firmware (web interface, drag and drop)
python3 tools/openjooki/installer_web.py          # Mac / PC / Linux
python3 tools/openjooki/installer_web.py --lan    # + drive it from your phone
```

## Contact

Guillain d'Erceville — guillain@poulpe.us

## License

MIT. Use at your own risk; the tool is designed to be safe, but always keep a backup.
