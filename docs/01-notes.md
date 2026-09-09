# Jooki v2 — Recovery notes

_Session of September 9, 2026 — regained access to the household Jooki._

## In one sentence
The Jooki was neither broken nor "bricked": it works, it was just unreachable
via `jooki.local`. Its real network name and IP were tracked down, the web
interface responds, and we can add music again.

## How to reach it (IMPORTANT)
- **Stable address (bookmark this)**: http://jooki2-0426E8.local
- **Direct IP address**: http://192.168.1.61
- `jooki.local` does NOT work / no longer works — that is not this device's
  mDNS name. The correct name is `jooki2-0426E8.local`.
- From the interface: **Playlists → "Add a playlist"** to upload MP3s.
  "Characters" links a playlist to an NFC token.

## Device spec sheet (recorded on 2026-09-09)
| Item | Value |
|---|---|
| Network name (mDNS) | jooki2-0426E8 |
| IP (Wi-Fi, DHCP) | 192.168.1.61 |
| Wi-Fi MAC | A8:EE:C6:04:26:E8 |
| Wi-Fi signal | -48 dBm (excellent) |
| Storage | 4585 MB free, 11% used (≈ plenty of room) |
| Battery | 99%, charging via USB |
| Firmware | n20221206-5ce8778-70b40631 (Dec. 2022), ESP32_FIRMWARE_LOADED |
| Web UI | 3.5.4-3525ee48 |
| Spotify | account 11131405152 linked but inactive |
| Bluetooth | inactive |

## Playlists present (current state, to be refreshed)
- Carnaval des animaux ("Fantôme" token)
- Jooki - Blue (blue token) — nursery rhymes
- Jooki - Orange (orange token) — nursery rhymes
- Pierre et le loup ("Dragon" token)
- Tri Yann ("Baleine" token)
- Untitled Playlist (old blue token) — nursery rhymes

## Why it was unreachable
- The name `jooki.local` does not match this device (real name:
  `jooki2-0426E8.local`). mDNS resolution therefore failed.
- The original Jooki mobile app is dead since Muuselabs shut down: all
  management now goes through the local web interface.
- USB is useless: on the Jooki v2, USB mode is disabled from the factory
  (`JOOKI_DISABLE_USB=1`). When plugged in, it only charges — it exposes
  itself neither as a disk nor as a network peripheral.

## What to do to avoid losing access again
1. Bookmark http://jooki2-0426E8.local (Chrome / phone).
2. In the router (192.168.1.1), **reserve a static IP** for MAC
   A8:EE:C6:04:26:E8 so the address never changes again.

## "GitHub / tinkering" leads (to explore)
The community documented the Jooki after the company shut down. Useful if we
want to automate adding music or back up the content:
- Local web interface = endpoints `/upload`, `/config`, `/set_config`, `/ll`.
- An **MQTT broker** runs on port 1883 (no auth): topics
  `/j/web/input/DO_PLAY`, state on `/j/web/output/state`, LED via
  `/j/led/output/set_raw`. Lets you drive the Jooki from scripts.
- Root access is possible by adding your public SSH key via `/config`
  (`/mnt/config/jooki.conf`), then `ssh root@192.168.1.61`.
- References: nv1t.github.io/blog/reviving-jooki ,
  there.oughta.be/an/interface-for-jooki

### Project idea
A small tool (GitHub "Jooki" folder) that, locally, pushes MP3s from a folder
to the Jooki via `/upload` and creates/links the playlists automatically — so
we no longer depend on the dead app.

## Current goal
Put recent music back in place of the 5-year-old playlists.
Next step: point to the folder of MP3s to add, then create/update the
playlists via the web interface.
