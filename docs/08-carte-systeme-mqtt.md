# Jooki v2 — system map (the "everything laid flat" view)

_Inferred from the on-device code (root SSH, without opening the device, without
decrypting the ESP32). Original project: `ml-jooki-controllers` (Muuselabs), in
C + Lua._

## Core idea
The Jooki is a **set of small daemons wired together over a local MQTT bus**
(mosquitto, port 1883). Each daemon bridges a piece of hardware to `/j/...` MQTT
topics. **Huge consequence:** for a v3 firmware/app, we do NOT talk to the
hardware directly — we subscribe to the existing MQTT bus. The low-level
controllers (ESP32, LED, buttons, audio) stay black boxes.

## The daemons (launched by `ml-start-app.sh`, restarted in a loop)
| Daemon (bin/) | Role | Hardware |
|---|---|---|
| `esp32_ctrl` | ESP32 bridge | **WiFi + Bluetooth + NFC** (via `/dev/esps0` + `/dev/espnotif0`, **protobuf / ESP-Hosted**) |
| `gpio_ctrl` | buttons | GPIO |
| `ht_ctrl` | LED | light controller (`ht`) |
| `player` | audio playback | **ALSA** (libasound) + Lua (`player.lib`) |
| `web_ctrl` | web interface + API | serves the SPA, `/ll`, `/config`, `/upload`, real-time state |
| `spotify_ctrl` | Spotify Connect | (linked account, inactive) |

The Ingenic X1000 SoC has no radio: **the ESP32 provides WiFi/BT/NFC** to Linux
(network interface `ethsta0`, MAC read from `/sys/kernel/htdrv/mac`).

## MQTT bus — topic map (`input` = coming from hardware/state; `output` = commands to send)

### NFC (tokens) — the core
- `/j/nfc/input/tag` → **token placed** (contains the UID)
- `/j/nfc/input/tag_removed` → token removed
- `/j/esp32/output/nfc/tag/get`, `/j/esp32/output/nfc/mode/{get,set}`

### Audio (`player` daemon, ALSA)
- Commands: `/j/audio/out/{play,playOnly,cont,pauz,stop,seek,skip_sec,set_output_device}`
- State: `/j/audio/input/{starting,playing,paused,stopped,ended,position,error,device_changed}`
- Child volume limit: `/j/audio/{input,out}/toysafe`

### Buttons (`gpio_ctrl`)
- `/j/gpio/input/{next,prev,fwd,rew,vol_inc,vol_dec,vol_set,circle,hp_plugged,airplane_mode_on,airplane_mode_off}`

### LED (`ht_ctrl`)
- `/j/led/output/{set,set_raw,pulse,pulse_raw,charge_state}`

### Power / battery
- `/j/power/input/{battery_level,charging,plugged_in,charging_error}`
- `/j/power/output/{check_battery,print_state}`

### Network / Bluetooth (via ESP32)
- `/j/esp32/output/net/sta/{connect,disconnect,scan,provision,status}`
- `/j/esp32/output/net/{mac,mode,ip}/...`, `/j/esp32/output/bt/...`

### Spotify
- `/j/spotify/output/{play_preset,pauz,cont,next,prev,seek,set_vol,...}` / `/j/spotify/input/...`

### Miscellaneous
- `/j/all/quit` (shutdown), `/j/ht/output/raw_{read,write}` (low-level I2C)

## Data model (JSON, simple)
- `tokens.json`: mapping **token UID → playlist**
- `playlists.json`: playlist → list of tracks (+ character/token, artwork)
- `tracks.json`: track / event-sound definitions
System defaults: `/jooki/app/system/*.json`; **real data**:
`/jooki/external/jooki/` (backed up).

## Hardware interfaces (summary)
- **ESP32**: `/dev/esps0` (+`/dev/espnotif0`), **ESP-Hosted** protobuf → WiFi/BT/NFC.
  We do NOT need to decode it: `esp32_ctrl` already publishes everything over MQTT.
- **Audio**: ALSA (`libasound`), ALSA mixer for volume.
- **LED**: `ht_ctrl` (topics `/j/led/output/*`).
- **Buttons**: `gpio_ctrl` (topics `/j/gpio/input/*`).
- **Security**: signed remote commands (openssl, `/etc/rpc_cmd_verify.pub`).

## What this means for Jooki v3 (Path A, no hardware)
The "token → music" logic to rewrite fits in 3 conceptual lines:
1. subscribe to `/j/nfc/input/tag` → get the UID
2. look up the UID in `tokens.json` → the playlist
3. publish `/j/audio/out/playOnly` (keeping the stock `player`) **or** drive our
   own player (MPD)
+ buttons (`/j/gpio/input/*`), LED (`/j/led/output/set_raw`), battery
(`/j/power/input/*`). Our **web app** talks to the same MQTT bus (like `web_ctrl`).

→ So we can replace **the entire application layer and the interface** while
keeping the original hardware controllers as black boxes. This is the reliable,
maintainable base we're after, reachable **without opening the Jooki**.

## Next validation (already possible, we have root + MQTT)
- Listen to `/j/nfc/input/tag` while placing a token → confirm the UID format.
- Publish `/j/led/output/set_raw` → watch the LED change.
- Listen to `/j/#` → observe the full bus live.
