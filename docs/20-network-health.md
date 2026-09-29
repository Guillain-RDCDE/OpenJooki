# Network health: uploads that survive, logs that stay home, a `.local` name

Firmware 1.3.0. Music never needs the Wi-Fi (tokens and playback are local);
the page and the uploads do. This part makes them tolerate a weak Wi-Fi, and
removes what the original system did behind the family's back.

## What changed

**Uploads retry on their own.** A transfer cut by the network (or stalled for
30 s without progress) is sent again after 3, 8 then 20 s, once the Jooki
answers again: 4 tries per file, the queue never blocks. If the connection to
the Jooki drops while it is processing a file, the page checks after
reconnecting whether the file arrived before sending it again. After 4 failed
tries the file shows a clear error and a **Retry** button.

**Wi-Fi quality on the Settings page**: network, signal in dBm and in words
(good ≥ -65 dBm, fair ≥ -75, weak below), drops since start-up, and advice when
the signal is weak.

**Logs stay on the Jooki.** The original `syslog-ng` configuration sent every
log line to Muuselabs' Papertrail account (`logs6.papertrailapp.com:13434`):
playlist and token names, Wi-Fi name, errors. That destination is removed, and
the 11 MB queue of lines waiting to be sent is deleted at boot. The local log
was a single file growing forever on the memory card (39 MB, 340 000 lines on
our Jooki); it is now one file per weekday, overwritten after 6 days, without
the Wi-Fi driver's block-ack chatter (most of the volume). The end of the old
file is kept once as `syslog-ng.old.log` (3000 lines). The original
configuration is kept as `/etc/syslog-ng/syslog-ng.conf.openjooki-orig`.

**A name instead of an address.** The Jooki answers mDNS for its own name,
`<hostname>.local` (for example `jooki2-a1b2c3.local`, shown in Settings): the
page opens at `http://jooki2-a1b2c3.local/` from macOS, iOS, Windows 10+ and
recent Android, even when the router gives the Jooki another address. An
*extra* name (alias) is not possible: the Jooki's web server (`web_ctrl`,
closed) serves only the system's own hostname and redirects any other one to
Muuselabs' dead setup site. So with the 2.0 core the name itself can be
**changed** (Settings > Name > Rename, command `OJ_SET_NAME` / `device.set_name`):
lower-case letters, digits and inner hyphens, applied at once and kept in
`/data/openjooki/hostname`. At boot `ml-jooki-hostname.sh` applies it, and so
does the last sysinit line of `/etc/inittab` (it used to set the factory name
again after rcS). `/etc/hostname` always keeps the factory name, which stays
the device id. After a rename the old address stops answering. IPv6 queries get the standard "IPv4 only" answer (NSEC), so browsers do
not wait 5 s for an IPv6 address. The responder shares UDP 5353 with
`spotify_ctrl`'s own (which only announces `A8:EE:C6:A1:B2:C3.local`); if the
port could not be shared the Jooki simply works without the name.

## How it is built

- `tools/openjooki/system/syslog-ng.conf` replaces `/etc/syslog-ng/syslog-ng.conf`
  (installed by `jooki.py patch webui` and by `scripts/add-webui-to-image.py`;
  checked with the Jooki's own `syslog-ng --syntax-only`). Wi-Fi events are also
  copied to `/tmp/oj-wifi.log` (RAM).
- Module `ojnet` in `lua_patches.py`: log cleanup at boot, Wi-Fi state (drops and
  beacon losses from `/tmp/oj-wifi.log`, access point from the chip's own status)
  published in the state as `net`, and the mDNS responder (non-blocking UDP
  socket polled by the main loop).
- The page (`webui/app.js`): upload queue with retries, stall watchdog and
  after-reconnect check; Wi-Fi row in Settings.

## What we learned about the Jooki's Wi-Fi (26/09/2026)

- The Wi-Fi chip (ESP32, Muuselabs firmware "WCM") is **2.4 GHz only** and keeps
  up to a few networks in its own memory (`esp32_cmd list_configured_ap`).
- **It is sticky**: after a drop it first retries the *last* network it used,
  and only then the others. It never moves by itself to a stronger access point.
  On our Jooki, a short hiccup of the access point next to it (-44 dBm) sent it
  to the router at the other end of the house (-80 dBm), where it stayed.
- It runs in **maximum power-save mode** (`ps:2`, asleep ~76 % of the time, DTIM 3),
  which makes a weak link worse (beacon timeouts). No command exposed by the
  firmware changes it.
- `esp32_cmd disconnect` is refused by this firmware. **`esp32_cmd add_ap`
  crashes the chip** ("stack overflow in task pc_serial", then it reboots; 29/09),
  so a network is only ever given over Bluetooth. `esp32_cmd remove_ap` is safe,
  even for the network in use (the chip stays on it, "Already connected").
- What the chip remembers as its **last network** (`WCM_NVS: saving N ... as last
  connection`) is written only when it reconnects **by itself**; a network given
  over Bluetooth does not change it. At start it goes to that one; after a cut it
  tries the **next one in its list**, not the strongest, and that one becomes the
  last. So a Jooki that knows two networks can end up on the far one for good after
  one hiccup (ours: 29/09, the Livebox at -70 dBm instead of the mesh at -40).
  No command sets the preferred network: keep only the network near the Jooki.
- **Opening a Bluetooth set-up session takes the chip off its Wi-Fi** until it is
  given a network (29/09: one read of the list with a session left our Jooki offline
  until the watchdog restarted it; "apply" alone is refused). Reading the list and
  forgetting a network need no session. Since the next release the page and
  `jooki_wifi.py` open one only to look for networks or to give one, and say so.
- **Rescue without any Wi-Fi**: when it cannot connect, the chip advertises over
  Bluetooth as `JOOKI2_<id>` with Espressif's standard provisioning service
  (`b3562d79-…`, no security, protocol v1.1): a computer with Bluetooth can scan
  the networks the Jooki sees and give it a network in seconds. Endpoints:
  `prov-scan`, `prov-config`, `prov-session`, plus Muuselabs' `wcm-add-ap`,
  `wcm-list-config-ap`, `wcm-remove-ap`.
- Never remove the network that works before the new one is proven: the Jooki
  cannot be reached remotely without Wi-Fi.

## A safer start (29/09/2026, after the next release)

- **The chip can stay stuck** on "connecting" (28/09: unreachable, 18 drops since the
  start, back only through the Bluetooth page). Nothing on the original system wakes
  it: the core only read its state every 30 s. Since `disconnect` is refused, a
  restart is the way back, so the core does it (`services.network` watchdog): ten
  minutes offline in a row (`wifi_watchdog_s`), radios supposed on (no airplane mode),
  nothing playing, on the charger (on battery the Jooki switches itself off after
  15 min anyway). At most two restarts in a row (`wifi_watchdog_max`, the count in
  `/data/openjooki/wifi_watchdog`, back to 0 once online), none during an update
  (`/tmp/oj-updating`), and silent (`/data/openjooki/quiet_boot`: no ready chime).
- **The original start crashed the Wi-Fi chip at every boot.** The original
  `S55_ml-start-wifi.sh` ran `esp32_cmd add_ap mnet2 muuselabs256` (Muuselabs'
  factory network) at every boot, and `add_ap` crashes the chip: it rebooted in the
  middle of its first connection, the Wi-Fi came 70-80 s late (logs: `reconnecting
  to idx 1` at ~72 s, the network at ~81 s), tokens and sound were re-initialised,
  and on the way back it could settle on another network it knows. Since 2.0.8 S55
  no longer adds it (page back ~35 s after a restart on our Jooki); since the next
  release it writes nothing to the chip's list at start at all (2.0.8 removed mnet2
  there, while the chip connected), and the core forgets mnet2 a minute after the
  Wi-Fi is up (`wifi_forget_factory`: only if another network is known and the chip
  is not on it). S55 also waits 30 s for the chip instead of 10, and no longer writes
  `/data/mode/FACTORY` (for good) when the chip is slow: it logs instead.
- **The broker had no keeper**: if mosquitto failed to start or stopped, every
  daemon went deaf and nothing restarted it. The core starts it again after 20 s
  without it (`adapters.broker_watch`, only if it is not running), and no longer
  spins while it waits (the bus sleeps its turn when there is no broker).
- `S58_mosquitto.sh` no longer takes `/mnt/config/mosquitto.conf` (the card's FAT
  partition, writable from any computer) over the broker's own settings.
- **Trap for anyone replacing a start script**: the original is kept next to it
  (`/etc/rcS.d/S55_ml-start-wifi.sh.openjooki-orig`), and the boot loop runs every
  `S??*` file of that folder. OpenJooki's `rcS` skips `*.openjooki-orig`, or both the
  new and the original script would run (checked by `tests/test_robustness.py` R5).

## Tests

- `tests/test_net.py` (13): log cleanup, Wi-Fi state, access point without log
  event, `<hostname>.local` answered (any case), IPv6 query answered "IPv4 only",
  other names and record types ignored, malformed packets harmless.
- `tests/e2e.py` E20–E21: upload cut twice then added once, 4 failures then
  **Retry**, weak / good Wi-Fi shown, `.local` name shown.
- On the real Jooki: data kept, Papertrail queue and big log gone, weekday log
  in use, Wi-Fi chatter filtered, the `.local` name resolved from a Mac,
  no error in the new code.
