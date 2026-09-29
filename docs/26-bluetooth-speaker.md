# 26 — Bluetooth speakers and headphones

The Jooki 2 can play through a Bluetooth speaker or headphones. Jooki built it
into the firmware of the Wi-Fi/Bluetooth chip (ESP32-WROVER-E, firmware of
2 December 2022) and never offered it in the app. OpenJooki adds the button.

## For parents

1. Switch the speaker or headphones on and put them in **pairing mode**
   (usually: hold the Bluetooth button until the light blinks fast).
2. On the Jooki's page: **Settings → Bluetooth speaker or headphones → Search**.
3. Tap **Connect** next to your speaker. The sound moves to it.

If the speaker switches off, the sound comes back to the Jooki. When it is
switched on again, the Jooki reconnects by itself (no need for pairing mode
again). **Stop using this speaker** forgets it and keeps the sound on the Jooki.
Airplane mode switches Bluetooth off too.

## How it works

The ESP32 is an A2DP *source*: it already receives the Jooki's sound (the
speaker's audio goes through it), encodes it in SBC and sends it to the paired
device. Nothing runs on the Linux side apart from `esp32_ctrl`, the bridge
between the MQTT bus and the chip. The core (`core/services/bluetooth.lua`)
only sends it these messages. Measured on a real Jooki on 29 September 2026
with a Sony SRS-X11:

| Topic (`/j/esp32/…`) | Payload | Effect |
|---|---|---|
| `output/bt/start_scan` | anything | about 15 s of search; answers `input/bt/device_discovered` |
| `input/bt/device_discovered` | `{"name": "SRS-X11", "mac": "8C:DE:…", "rssi":-25, "cod":"0x00240414"}` | repeated many times per device, the name sometimes empty at first |
| `output/bt/connect_device` | `MAC<TAB>0xCOD<TAB>name` | **tab-separated, not JSON** (commas, spaces and JSON are refused) |
| `output/bt/set_autoconnect` | `true` or `false` | not `1`/`0`; with `true` the chip reconnects to the last device by itself |
| `output/bt/forget_device` | `MAC` | refused while autoconnect is on: send `false` first |
| `output/bt/get_state` | anything | answers `input/bt/state N`, `input/bt/device_connected {…}` when connected, and one `input/bt/device_saved {…}` per device the chip remembers (it remembers several) |

A speaker already paired **does not show in a search** unless it is put in
pairing mode again, but reconnecting to it needs no pairing mode. So the page
lists the remembered speakers first, each with its own *Connect* button.

States: 0 idle, 1 scanning, 2 scan ended, 3 scan failed, 4 connecting,
5 connected, 6 connect failed, 7 forgotten, 8 forget failed, 9 disconnected.

**The chip does not say when a speaker goes away or comes back**: no message
on the bus. The core asks `get_state` every 30 seconds. **Nor does it always
say that a search ended**: it can keep answering state 1 long after. The core
closes a search itself after 20 seconds and ignores that stale 1 afterwards. Only audio devices
(major class of device 0x04) are listed.

`esp32_ctrl` logs to `/jooki/external/logs/syslog-ng/jooki-<Day>.log`
(`esp32_ctrl.c:` lines, and the chip's own `BLUETOOTH:` lines through `esp_tty`).

## Not verified yet

- Wired headphones plugged in while a Bluetooth speaker is connected (the
  headphone jack is driven by the main processor, not by the ESP32).
- The volume limit for children (*toy-safe*) applied to a Bluetooth speaker.
- The sound delay with headphones (A2DP adds a fraction of a second).
