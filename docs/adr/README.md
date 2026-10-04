# Architecture decision records

One page per structural decision: the context, the decision, the alternatives
considered, the consequences. A record is never edited after acceptance; a
change is a new record that supersedes it. Numbering is chronological.

Because the records are not edited, some sentences in them describe what was
intended and was then built differently. The **As built** column says where
(read from the code of release 2.2.7; the full picture is
[21-architecture-2.0.md](../21-architecture-2.0.md), whose §15 lists what was
planned and never built).

| # | Decision | Status | As built (2.2.7) |
|---|---|---|---|
| [0001](0001-keep-the-c-host-and-lua-5.1.md) | Keep the C host and Lua 5.1 for the 2.0 core | accepted, shipped in 2.0.0; its size budget (176 KiB) **superseded** by 0010, then 0011 | the decision stands; the core is no longer bound by the host's buffer (0011), CI guards it at 400 KiB |
| [0002](0002-rewrite-not-patch.md) | Rewrite the application from scratch instead of patching it further | accepted, shipped in 2.0.0; its consequences on the 1.x bench and `lua_patches.py` **superseded** by 0012 | the 1.x bench was the oracle for the switch, through the v1 layer; it and `lua_patches.py` are gone (0012) |
| [0003](0003-event-loop-and-pure-handlers.md) | One event loop, pure handlers, ports and adapters | accepted, shipped in 2.0.0 | the loop waits on the bus socket and the web server's sockets; the mDNS socket is polled once per turn, not selected. No lint rule forbids a service to require an adapter: none does, by review |
| [0004](0004-keep-1x-data-files.md) | Keep the 1.x data files and formats (reversibility) | accepted, shipped in 2.0.0 | writes are `.tmp` → keep `.bak` → rename, **without `fsync`** (a `sync` at shutdown); every file is still version 1, no migration exists |
| [0005](0005-contract-v2.md) | A versioned contract with revisioned state and typed errors; v1 kept one release | accepted, shipped in 2.0.0 | v1 is **still served** and is what the page speaks; there is no separate position message; the schemas are Lua tables in the code (no `docs/api/v2/` folder was ever made), printed into [api-v2.md](../api-v2.md) |
| [0006](0006-third-party-code.md) | Third-party code: minimal, vendored, pinned | accepted, shipped in 2.0.0 | the MQTT client is `adapters/mqtt_codec.lua` (84 lines) + `adapters/bus.lua` (171 lines); md5 is **not** in Lua: the shell action `md5` runs `md5sum`; there is no `VENDOR.md`: the one vendored file is `core/vendor/json.lua` with `json.LICENSE` next to it |
| [0007](0007-security-model.md) | Close root execution over HTTP; bind MQTT to localhost; password on the WebSocket | accepted, fully built (2.1.0) | no one-time code: an optional 4-digit **parent code** gates the changes (v1 and v2). The WebSocket password is in `/data/openjooki/ws_secret` (not `/mnt/config`), served at `/oj-auth.json`. There is no `--legacy-open-mqtt`: the switch is *MQTT on the LAN* in Settings (`mqtt_lan`), with the password |
| [0008](0008-no-shell-in-the-hot-loop.md) | No shell processes or temp files in the loop | accepted, shipped in 2.0.0 | the named actions are those of `core/adapters/shell.lua`: there is no `reboot`, `factory_reset` or `wifi_add` action. No DHCP event is subscribed to: the address comes from the ESP32's status, asked every 30 s with a read of `/proc/net/route` |
| [0009](0009-keep-spotify-deezer.md) | Keep Spotify Connect and Deezer as an optional module | accepted | as written (`services/streaming.lua`, `--without services.streaming`) |
| [0010](0010-size-budget-192.md) | Raise the stripped size budget from 176 to 192 KiB (host limit stays 200) | **superseded** by 0011 | no 192 KiB check exists any more |
| [0011](0011-core-in-its-own-file.md) | Put the core in its own file `/jooki/lib/core.lua`; `player.lib` becomes a loader (no 200 KiB ceiling on the core) | accepted | as written; `bundle.py` defaults to a 512 KiB limit and CI passes `--max-kib 400`; the stripped core of 2.2.7 is about 218 KiB |
| [0012](0012-retire-1x.md) | Retire the 1.x patched program and its tooling (`lua_patches.py`, 1.x bench, `playlist`/`music`/`cut-cloud`/`harden`); `--core` required | accepted | as written; the history label it asks for on [22-core-inventory.md](../22-core-inventory.md) is now there |
