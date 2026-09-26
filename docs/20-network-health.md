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
`<hostname>.local` (for example `jooki2-0426e8.local`, shown in Settings): the
page opens at `http://jooki2-0426e8.local/` from macOS, iOS, Windows 10+ and
recent Android, even when the router gives the Jooki another address. A shorter
`jooki.local` is not possible: the Jooki's web server (`web_ctrl`, closed)
serves only its own name and redirects any other one to Muuselabs' dead setup
site. IPv6 queries get the standard "IPv4 only" answer (NSEC), so browsers do
not wait 5 s for an IPv6 address. The responder shares UDP 5353 with
`spotify_ctrl`'s own (which only announces `A8:EE:C6:04:26:E8.local`); if the
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
- `esp32_cmd remove_ap`/`add_ap` reuse the same memory slot, so they do not
  change the order; `esp32_cmd disconnect` is refused by this firmware.
- **Rescue without any Wi-Fi**: when it cannot connect, the chip advertises over
  Bluetooth as `JOOKI2_<id>` with Espressif's standard provisioning service
  (`b3562d79-…`, no security, protocol v1.1): a computer with Bluetooth can scan
  the networks the Jooki sees and give it a network in seconds. Endpoints:
  `prov-scan`, `prov-config`, `prov-session`, plus Muuselabs' `wcm-add-ap`,
  `wcm-list-config-ap`, `wcm-remove-ap`.
- Never remove the network that works before the new one is proven: the Jooki
  cannot be reached remotely without Wi-Fi.

## Tests

- `tests/test_net.py` (13): log cleanup, Wi-Fi state, access point without log
  event, `<hostname>.local` answered (any case), IPv6 query answered "IPv4 only",
  other names and record types ignored, malformed packets harmless.
- `tests/e2e.py` E20–E21: upload cut twice then added once, 4 failures then
  **Retry**, weak / good Wi-Fi shown, `.local` name shown.
- On the real Jooki: data kept, Papertrail queue and big log gone, weekday log
  in use, Wi-Fi chatter filtered, the `.local` name resolved from a Mac,
  no error in the new code.
