# The current core, function by function (inventory for the 2.0 rewrite)

Source: the Jooki v2 application `player.lib` (Muuselabs, firmware
`n20221206-5ce8778-70b40631`), 5 508 lines of minified Lua 5.1 once decoded,
plus the 49 OpenJooki patches of 1.3.0 (5 673 lines). Read in full on
26/09/2026; measurements taken on a live Jooki v2. This document is the
reference for **what the new core must do** (docs/21) and for **what it must
not repeat**.

The original program is not distributed by OpenJooki; this inventory describes
its behaviour, not its code.

## 1. How the program is loaded and runs

| | |
|---|---|
| Host | `/jooki/bin/player` (C, closed): reads `/jooki/lib/player.lib`, undoes the 2-byte XOR, inflates with miniz into a **200 KiB** buffer, `luaL_loadbuffer`, runs it. Full standard libraries (`io`, `os`, `debug`…), LuaSocket and LuaFileSystem available from `/usr/lib/lua/5.1`. |
| Given by the host | `c_alsa_set_volume(v, x)` (ALSA mixer), `c_syslog(severity, msg)`, `c_isTerminating()` (SIGTERM seen?), `c_sd_notify()` (systemd-style "ready"). Nothing else: the program **runs its own loop** inside the chunk and never returns. |
| Environment | `id`, `hostname` (note: with `.local` appended), `ip` (empty at start), `wifi_mac`, `machine` (`ml-j2000`), `firmware`, `wlan_interface` (empty), `JOOKI_LOG_LEVEL`. |
| Supervision | `ml-launch-controller.sh`: restarts the process after 1 s on any non-zero exit (except 137/143). All in-memory state is lost on restart. |
| Loop | `broker.runForever(tick, 0.5)`: `select` on the MQTT socket for 0.5 s, dispatch one message, run `tick`. **Everything is single-threaded**. |
| Memory / time | RSS 2.9 MB; ready 10 s after the process starts (`uptimeToReady`); the whole device has 27 MB RAM. |
| Root filesystem | mounted `rw,sync`; `/tmp` is **not** a separate mount on our Jooki (only `/run` and `/var/volatile` are tmpfs). |

## 2. Modules (21) and what becomes of them

| Module | Lines | Role | 2.0 |
|---|---|---|---|
| main chunk | 1 261 | wiring: state document, topic table, init, system tags, power, Wi-Fi, web handlers | **rewrite** as `kernel` + `api` + small services |
| `Catalog` | 1 029 | playlists / tracks / tokens database, uploads, unused tracks, play actions | **rewrite** as `library` (+ `playback` for actions) |
| `audio` | 579 | playback state, next/prev, system sounds, Spotify/Deezer glue | **rewrite** as `playback`; Spotify/Deezer glue **ported** into an optional `streaming` module |
| `jplay` | 170 | "Jooki Play" cloud streaming (dead service, hard-coded API key) | **drop** |
| `leds` | 168 | colours, groups, event → light mapping | **rewrite** as part of `device` |
| `audiocfg` | 134 | volume, shuffle, repeat, headphones; ALSA + `audiocfg.json` | **rewrite** as part of `device` |
| `sys` | 132 | shell execution with temp files, file helpers | **replace** by `adapters.files` / `adapters.shell` |
| `syscmd` | 121 | flags in `/data/mode`, uptime, Wi-Fi status via shell, disk usage | **replace** (flags kept, shell-outs removed) |
| `jsondb` | 105 | JSON files with `_.version`, dirty tracking, `.new` → rename → `.bak` | **rewrite** as `adapters.files` (+ fsync, migrations) |
| `keys` | 83 | button presses, long presses, 4-button combo | **port** into `device` |
| `broker` | 84 | MQTT client wrapper, topic → handler table (with 1.x `pcall` guard) | **rewrite** as `adapters.bus` + `kernel.dispatch` |
| `power` | 62 | inactivity shutdown (14/15 min) | **port** into `device` |
| `bluetooth` | 19 | remembers the connected BT device | **port** (2 fields) |
| `discovery` | 19 | cloud heartbeat (`heartbeat.sh`, neutralised by OpenJooki) | **drop** |
| `bytes` | 9 | hex helpers | trivial |
| `time` | 8 | `socket.gettime` | `adapters.clock` |
| `util` | 12 | safe `string.format` | trivial |
| `log` | 90 | levels, dump, `c_syslog`, `fatal` = exit | **rewrite** as `kernel.log` (structured, rate-limited, no exit) |
| `JSON` | 656 | J. Friedl's JSON.lua (MIT) | **replace** by a smaller vendored library |
| `paho.mqtt` + `paho.utility` | 556 | old Paho Lua client (EPL) | **replace** by a minimal in-house client |
| `sha1` | 211 | kikito sha.lua (MIT), used only to shorten Spotify URIs in logs | **drop** |
| `ojbed`, `ojnet` (OpenJooki 1.3) | 420 | bedtime, network health, mDNS | **port** (already written test-first) |

Third-party code is 1 423 of 5 508 lines (26 %). Jooki Play, the cloud
heartbeat and the Mender client are about 250 lines that do nothing useful
since the services closed. Spotify and Deezer paths (about 350 lines) are
kept in 2.0 as an optional module: the `spotify_ctrl` daemon is still on the
device and some families may use it.

## 3. The main chunk, piece by piece

### 3.1 State document (`t`)
Published whole on `GET_STATE` and after most commands, or partially (one
sub-tree) with `publish_partial(filter)`: `.db`, `.nfc`, `.device`, `.wifi`,
`.bt`, `.power`, `.jplay`, `.bluetooth`, `.audio.config`, `.mender`,
`.userMessages`, `.spotify`, `.deezer`, `.db,.device`, `.jplay,.db`, and
(OpenJooki) `.bedtime`, `.net`.

```
userMessages[]           {id, timestamp, level, messageType, extra}
nfc                      {starId, tagId}
audio.config             {volume, headphones_en, shuffle_mode, repeat_mode}
audio.playback           {state, position_ms}          -- state: STARTING PLAYING PAUSED STOPPED ENDED
audio.nowPlaying         {album, artist, audiobook, duration_ms, hasNext, hasPrev, image,
                          playlistId, service, source, uri, track, trackId, trackIndex, queueIndex}
wifi                     {ssid, bssid, ch, signal, crypt, stat, ip}   -- copied from esp32_ctrl
bt, bluetooth            '' / {connected_mac, devices}
power                    {connected, charging, level{mv, p (tenths of %), t (m°C)}}
mender                   {state, event}
device                   {flags, toy_safe, id, hostname, ip, wifi_mac, machine, firmware,
                          openjooki, diskUsage{used, available, total, usedPercent}, usage (df -h text)}
db                       {playlists, tracks, tokens}   -- the live tables of the catalog
spotify, deezer, jplay   dead services
bedtime, net             OpenJooki 1.3
```

The page receives `audio.playback` **every second** while playing (one
position event per second → one partial publish).

### 3.2 Inbound topics (the handler table)

Every handler is wrapped: JSON decode (rejected with `received invalid message`
if invalid), call, publish the returned error on `/j/web/output/error`, then
publish the sub-tree named by the wrapper. Since 1.3 a Lua error inside a
handler is caught (`ERR_HANDLER`) instead of killing the process.

**Page → Jooki (`/j/web/input/…`)**

| Message | Payload | Effect |
|---|---|---|
| `CONNECT` | — | plays the "connect" sound (Evt.Mobile.connect), does not pause music |
| `GET_STATE` | — | publishes the whole state |
| `MESSAGE_DISMISS` | `{id}` | removes a user message |
| `SWITCH_LOCALE` | `{locale}` | runs `lang_set.sh` (voice language) |
| `PLAYLIST_PLAY` | `{playlistId, trackIndex?}` | plays (system catalog can play too) |
| `PLAYLIST_NEW` | `{title, audiobook?, star?}` | creates `user_<time>[_n]` |
| `PLAYLIST_NEW_SPOTIFY` / `_DEEZER` | … | dead |
| `PLAYLIST_ADD_TRACK` | `{playlistId, trackId}` | appends |
| `PLAYLIST_ADD_STREAM` | `{playlistId, title, url}` | web radio track `stream_<time>` |
| `PLAYLIST_ADD_FILE` | `{playlistId?, filename}` | imports a file already in `uploads/` |
| `PLAYLIST_ADD_UPLOAD` | `{playlistId?, uploadId, filename}` | see 4.3 |
| `PLAYLIST_UPDATE` | `{playlist{id, title?, star?/tagId?, tracks?, audiobook?}}` | rename / link / reorder / remove / flag |
| `PLAYLIST_DELETE` | `{playlistId}` | tracks go to "Unused tracks" |
| `TOKEN_EDIT` | `{tagId, name?, image?}` | label a physical token |
| `TOKEN_DELETE` | `{tagId}` | forget a token |
| `DO_PAUSE` `DO_PLAY` `DO_NEXT` `DO_PREV` | — | transport (next/prev "forced": work while paused) |
| `SEEK` | `{position_ms}` | |
| `SKIP_SEC` | `{delta_s}` | |
| `SET_VOL` | `{vol}` | 0–100, clamped |
| `SET_CFG` | `{shuffle_mode?, repeat_mode?}` | saved at once (1.3) |
| `SET_TOY_SAFE` | `{enable}` | flag `TOY_SAFE_OFF`, `toy_safe_update.sh`, ESP32 toysafe |
| `SET_WIFI` | `{ssid, password}` | `wifi_add_network.sh` (restarts Wi-Fi) |
| `SHUTDOWN` | `{src}` | save, stop, `/j/all/quit`, poweroff |
| `OJ_UPDATE_CHECK` / `OJ_UPDATE_START` | — | OpenJooki 1.2 (curl in background, status files) |
| `OJ_SLEEP` / `OJ_BEDTIME_SET` / `OJ_RESUME_RESET` | see docs/19 | OpenJooki 1.3 |
| `jplay/*`, `DEEZER_GET_PLAYLISTS`, `SET_CFG_DEEZER` | | dead |

**Daemons → Jooki**

| Topic | Payload | Handler |
|---|---|---|
| `/j/audio/input/{starting,playing,paused,stopped,ended}` | `{id}` (3 = system sound, 7 = music) | playback state machine |
| `/j/audio/input/position` | `{id, pos}` every second | position |
| `/j/nfc/input/tag` | `"<UID 14 hex>,<star hex>"` | token placed (4.4) |
| `/j/nfc/input/tag_removed` | — | pause, clear `nfc` |
| `/j/nfc/input/tag_written` | tagId | after writing a blank token |
| `/j/gpio/input/{next,prev,fwd,rev,vol_inc,vol_dec,circle,airplane_mode_on/off,airplane_release}` | `"1"`/`"0"` | buttons (keys module) |
| `/j/gpio/input/vol_set` | `{vol}` | knob |
| `/j/power/input/{battery_level,plugged_in,charging}` | `{mv,p,t}` / 0-1 | power |
| `/j/esp32/input/net/sta/config` | `{ssid,bssid,ch,signal,crypt,stat,ip}` | Wi-Fi state → lights, state |
| `/j/esp32/input/knobs/state` | `{volume, control, hp_state}` **every second** (polled) | volume knob, headphones |
| `/j/esp32/input/bt/{device_connected,state}` | | bluetooth |
| `/j/net/dhcp/{bound,renew}` | | refresh IP |
| `/j/mender`, `/j/mender/shutdown_app` | `"<state>_<event>_"` | OTA events (dead Mender server) |
| `/j/event` | `Evt.*` name | system events from shell scripts (Wi-Fi setup…) |
| `/j/cloud/input/tag_new_write` | | dead cloud |
| `/j/debug/input/{crash,suspend,dump,ping}` | | debug |

**Jooki → daemons (commands)**

`/j/audio/out/{play "id\turi", pauz id, cont id, stop id, seek "id\tms",
skip_sec "id\ts", set_output_device}`, `/j/led/output/{set_raw "GROUP,r,g,b",
pulse_raw "GROUP,r,g,b,n,ms,duty"}`, `/j/esp32/output/{net/sta/status,
knobs/state, nfc/mode/set, device/send_all_notifications, audio/set_toysafe}`,
`/j/nfc/out/write`, `/j/all/quit`, `/j/debug/output/pong`, `/j/web/output/{state,error}`.

### 3.3 Timers (`d` table, checked every 0.5 s tick)

| Timer | Period | What it does | Cost |
|---|---|---|---|
| heartbeat | 2 min | cloud `heartbeat.sh S_LIVE` (neutralised) | — |
| inactivity | 30 s | `power.tick`: shutdown after 15 min idle on battery | — |
| powerwarn | 5 min | low-battery warning while < 20 % | — |
| wifistatus | 10 s | asks esp32_ctrl for the station status | 1 message |
| **ipstatus** | **1 s** | `flagExists('WIFI_OFF')` (shell `test -e`) then **`wifi_ip.sh` (shell)**; publishes `.device` if the IP changed | **2 processes per second** |
| **knobs_state** | **1 s** | asks esp32_ctrl for knob position → `SET_VOL` path → ALSA | 1 message + ALSA call per second |
| arpupdate | 30 s | `arping` (shell) to keep the router's ARP entry | 1 process |
| keys `on_tick` | 0.5 s | long-press detection | — |
| bedtime / net (1.3) | 0.5 s / 15–20 s | fade, night window, Wi-Fi log, mDNS socket poll | reads |

`sys.execute` runs every shell command through **two temporary files**
(`os.tmpname`, stdout and stderr) that it reads back and deletes: with `/tmp` on
the `sync`-mounted root, that is four synchronous flash writes per shell call.
Baseline on an idle Jooki: about 3 processes and 8 flash writes **per second**.

### 3.4 Start-up (`e.init`)

1. connect to the broker (fatal if it fails → exit → restart loop);
2. load the system catalog (`/jooki/app/system`: event sounds), fatal if missing;
3. load/create the user catalog (`/jooki/external/jooki`), migrate, rebuild
   "Unused tracks"; set up `/tmp/web_ctrl_dirs` (symlinks for `web_ctrl`);
4. disk usage (`df` shell), `state.db` = live tables; register the handler table;
5. init modules; read `plugged`; headphones off; `c_sd_notify`;
6. ask the ESP32 for all notifications, NFC mode 1; read the IP;
7. `Evt.Jooki.Ready` (sound + lights), then flags `WIFI_OFF`+`BT_OFF` → airplane
   lights, `FACTORY` → warning lights.

### 3.5 System tags and events

NFC "star" codes 768–1023 are **system tags** (`sys.record`, `sys.factory_mode_*`,
`sys.airplane_mode_*`, `sys.toy_safe_*`, `sys.wifi_*`, `sys.bt_*`,
`sys.production_*`, `sys.factory_reset`), 1024–1056 **test tags** (play test
sounds), 2304–2313 `Jooki.Temp*`. Any unknown code becomes `new.<hex>` and
still works as a character. Character codes: 256–269 (`Jooki.*` figurines),
512 (`Jooki.Flat`), 528–535 (`G2.*` coloured tokens).

System events (`Evt.*`, 33 names) drive lights and, for six of them, a sound
from the system catalog (`Evt.Jooki.Ready`, `Evt.Character.Write`,
`Evt.Mobile.connect`, three factory voices). `systemEvent(name, nextCb)` pauses
the music, plays the sound on stream 3, resumes the music when the sound ends
if it was playing (`w` flag), and calls `nextCb` (used for "play the shutdown
sound, then power off").

### 3.6 Power, battery, heat

- battery `p` < 10 % → `Evt.Power.Low.Shutdown` then poweroff; < 20 % → warning
  every 5 min; not while charging;
- temperature > 80 °C → toysafe on, volume 80, `power_overheat.sh`;
- inactivity: 14 min → `powerWarn` (no-op lights), 15 min → poweroff, unless
  `STAY_ON` flag, Bluetooth connected, playing, or plugged in. "Alive" = any
  bus message on an `/input/` topic **except** `power`, `ht`, `esp32`, `audio`;
- plug/unplug toggles the USB mux (`/sys/kernel/htdrv/usb_mux`) and lights;
- `circle` button held 2 s → `POWEROFF from-button`; the four transport buttons
  together → `SPEAK_INFO` (voice announces the IP, `speak_info.sh`).

### 3.7 Lights (`leds`)

Groups `RING CIRCLE PREV NEXT VOL_INC VOL_DEC ALL`; colours as `r,g,b` 0–200.
Idle: ring white; playing with a token: **ring off**, without token: white.
`PREV`/`NEXT` show Wi-Fi: orange = not associated / no IP, white = ok;
light-blue while starting audio or when a token is detected; green pulse after
writing a token; yellow pulse for warnings; red pulse for errors; `powerOff`:
all off + circle red; `powerSuspend`: circle dim orange. Most `Evt.*` cases
are empty functions.

## 4. The catalog (`Catalog`) in detail

### 4.1 Files and tables
`playlists.json`, `tracks.json`, `tokens.json` (each `{"_":{"version":1}, …}`),
in `/jooki/external/jooki/`; `uploads/` (files named by track id),
`artwork/<id>.jpg`. `file2id` maps filename → id (memory). Loading (`revert`):
delete tokens with invalid UID, normalise `Jooki.Flat.Dragon`, warn when a
playlist has both `tagId` and `star`, upgrade Spotify presets, migrate per-token
links (1.3), add every track (`addTrack` in "loading" mode: missing files only
logged), drop orphan web radios, rebuild "Unused tracks".

### 4.2 Playlists
`{title, tracks[], star?, tagId? (legacy), audiobook?, image?, plType?
(JPLAY), spotify?, deezer?}`. Ids `user_<unix time>[_n]`, `TRASH` (pseudo
playlist "Unused tracks", read-only since 1.3, rebuilt after every change),
`system` (event sounds), `jplay_*` (dead). Operations: add, delete, rename,
link/unlink a character (one playlist per character), reorder/remove tracks
(removing from `TRASH` deletes the files that are really unused), set
`audiobook`.

### 4.3 Uploads and tracks
`web_ctrl` writes `uploads/upload_<id>`; the page then sends
`PLAYLIST_ADD_UPLOAD`. The program: md5 of the file (shell) → track id = first
16 hex; if known and present → duplicate, temp removed; else rename to
`uploads/<id>`, probe with `ml-audio-probe-wrapper.sh` (ffprobe-like, JSON in a
temp file), extract title/album/artist/duration/codec and the embedded image
(`artwork/<id>.jpg`), add the track, append to the playlist, refresh unused,
publish `.db,.device` (disk usage via `df`). Failure → user message
`UPLOAD_FAIL[_TYPE]` (1.3: never deletes an existing file). Track record:
`{filename, userFilename, size, codec2, format2, duration, title, album,
artist, hasImage}`; web radios: `{title, filename=url, isUrl=true}`.

### 4.4 Playing (`actionPlay*`, `audio`)
`actionFor(starId, tagId)` finds the playlist of the character →
`actionPlayGStreamer(playlistId, {trackIndex|queueIndex})`: queue = identity or
a per-playlist shuffled order kept in memory (not for audiobooks), track =
requested or `lastPlayed[playlist]` (memory; 1.3 adds `resume.json` for
audiobooks) or 1; builds `nowPlay{uri=file://…, service=FILE|STREAM, …}`.
`audio.play(nowPlay)`: if the same track is paused → continue; if playing →
ignore; else stop current, `/j/audio/out/play "7\t<uri>"`. `ended` on stream 7
→ repeat-one (not audiobooks) or `nextFileAction(+1)` (repeat-all wraps, else
stop). `prev` restarts the track when > 5 s in. `fwd`/`rev` are not implemented.
Token removed → pause (Spotify/Deezer variants dropped).

### 4.5 Tokens
`tokens.json`: `UID → {starId, seen, name?, image?, write?}`. A tag event
increments `seen`, learns the character (`updateTokens`), and if a `write`
request is pending sends `/j/nfc/out/write` (blank token programming).

## 5. Volume (`audiocfg`)
`set(v)`: clamp 0–100 → `c_alsa_set_volume` → `audiocfg.json` (dirty).
`inc/dec` ±10. Headphones: switch ALSA output device and amplifier
(`/sys/kernel/htdrv/amp_en`). **The knob's absolute position is re-applied every
second** (knobs_state), so any software limit must sit between `set` and ALSA
(that is where OpenJooki 1.3 put the night limit and the fade). Toysafe is a
separate hardware-side limit handled by the ESP32.

## 6. Shell scripts still needed by the application
`errorbeep.sh`, `lang_set.sh`, `toy_safe_update.sh`, `speak_info.sh`,
`record.sh` (voice memo token), `radio.sh` (Wi-Fi/BT on/off), `wifi_ip.sh`,
`wifi_signal.sh`, `wifi_add_network.sh`, `factory_reset*.sh`,
`fast_restart.sh`, `suspend.sh`, `power_overheat.sh`, `bt_list_conns.sh`,
`is_mounted.sh`, `ml-audio-probe-wrapper.sh`. Plus `sync`, `md5sum`, `find`,
`ffmpeg` (artwork), `arping`, `killall`, `reboot`, `poweroff`, `df`.

## 7. Defects and costs to leave behind (found while reading)

1. **Shell-outs in the hot loop** (3.3): ~3 processes and ~8 synchronous flash
   writes per second on an idle Jooki. 2.0: read `/sys`/`/proc` directly, keep a
   single long-lived IP source (DHCP event), no temp files, scratch in tmpfs.
2. **Position spam**: a state publish per second to every page while playing;
   fine on a good Wi-Fi, wasteful on a weak one. 2.0: position in a light
   dedicated event, state revisions.
3. **Memory-only playback memory**: shuffle order and last track vanish on
   restart; a broker hiccup (`Lost mqtt connection` → `rawFatal` → exit) forgets
   what was playing. 2.0: reconnect with backoff instead of exiting; resume
   state on disk (1.3 did it for audiobooks only).
4. **Untyped errors**: free-text messages the page pattern-matches.
5. **Handlers reach everywhere**: closures over 30 upvalues, one-letter names,
   state mutated from anywhere; no way to test a handler without the whole
   program. 2.0: pure handlers, adapters.
6. **Dead weight**: Jooki Play (hard-coded API key), cloud heartbeat, Mender
   client, `sha1`, factory/production tags: ~1 500 lines with the libraries.
   (Spotify/Deezer are kept by decision, isolated in their own module.)
7. **Security**: `web_ctrl` `/ll?action=` executes any command as root for any
   device on the Wi-Fi; `mosquitto` listens on all interfaces (1883 and 8000)
   without authentication. Not the Lua's fault, but the Lua is what talks to
   them.
8. **Lights**: the ring goes **off** while a token plays; Wi-Fi state on the
   transport buttons is easy to mistake for a fault (the "two orange dots").
   2.0: a clear, documented light language.
9. **`hostname` env carries `.local`**; `ip` env is empty; `wlan_interface`
   empty (so `arping` runs with an empty interface).
10. **Every write = full rewrite** of the JSON file (fine at this size, but
    `tracks.json` grows with the library; 156 tracks today).

## 8. Numbers to design against

| | measured |
|---|---|
| player.lib source (decoded) | 114 KB original, 132 KB with 1.3 patches; limit 200 KiB |
| RSS of the application | 2.9 MB (device: 27 MB total, ~10 MB available) |
| boot → ready | 10 s |
| library | 8 playlists, 156 tracks, 17 tokens (this family) |
| bus traffic idle | ~4 messages/s (knobs, ip, position when playing) |
| token → sound | < 1 s (measured by ear; to instrument in 2.0) |
