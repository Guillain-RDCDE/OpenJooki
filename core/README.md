# OpenJooki core

The Jooki's application, written from scratch: readable Lua 5.1 modules, built
into the format the Jooki's C host loads. How it is built, section by section:
`docs/21-architecture-2.0.md`; what it replaced: `docs/22-core-inventory.md`;
decisions: `docs/adr/`.

```
kernel/     loop, dispatch, timers, state, commands, log, config   (no I/O)
adapters/   bus (MQTT) + mqtt_codec (its packets) · files (atomic JSON) · clock · host (C functions)
            shell (named actions) · mdns (the .local name) · httpd (the page, /upload) · broker_watch (restarts mosquitto)
api/        v2 (schema-validated) · v1 (what the page speaks) · bus_events (bus topics → typed events) · schema (the validator)
services/   library · tokens · playback · device · uploads · bedtime · network · bluetooth · security · update · streaming · util (shared pure helpers)
  playback/   sounds (system sounds, stream 3) · resume (resume.json rules, save timer) · queue (shuffle order)
  device/     lights (ring, dots, Wi-Fi chase, party) · power (battery, cable, inactivity, power-off) · radio (toy-safe, radios, airplane) · buttons (presses, long-press tick)
fakes/      in-memory adapters for the specs (clock, bus, files, host, shell)
vendor/     third-party code (json.lua, MIT), pinned
spec/       unit specs (*_spec.lua) and integration (spec/integration/)
main.lua    wiring only
```

Rules: a service never requires an adapter; a handler is
`(doc, event) -> { state = {...}, commands = {...} }` and does no I/O; every
side effect is a command executed by the kernel. These three are kept by review
(no CI check enforces the layering; luacheck only checks globals and unused
names). Every module has its spec in `spec/`, except `services/util.lua`, which
is exercised through the others. The built core stays under the 400 KiB guard of
CI (ADR-0011: the core is its own file, only the loader is bound by the host's
200 KiB; `bundle.py --without services.streaming` builds a lean core without
Spotify/Deezer, ADR-0009).

## Run

```sh
lua5.1 core/spec/run.lua                                   # unit specs (no dependency)
lua5.1 core/spec/run.lua core/spec/integration/bus_spec.lua  # needs mosquitto on 127.0.0.1:1883
python3 tools/build/bundle.py                              # build/core.lua, core.min.lua, player.lib
python3 core/spec/integration/smoke.py                     # boots the built core against mosquitto
luacheck core                                              # lint (.luacheckrc at the repo root)
lua5.1 tools/build/apidoc.lua > docs/api-v2.md             # the v2 contract, generated from the code
```

These need `lua5.1 lua-socket lua-filesystem mosquitto luacheck` and the Python
packages of `tools/openjooki/tests/requirements.txt` (`paho-mqtt` 2.x: the Ubuntu
package is 1.x). The bench suites (`tools/openjooki/tests/`, see its README) also
need `ffmpeg` and Playwright's Chromium.

Environment variables the core reads (`main.lua`): `OPENJOOKI_CONFIG` (a JSON
file of configuration overrides, keys of `kernel/config.lua`), `OJ_HTTP_PORT`
(the web server's port, for the bench), `JOOKI_LOG_LEVEL=debug` or
`OPENJOOKI_LOG=<level>` (the log level).

CI (`.github/workflows/ci.yml`) runs on a push to `main` and on pull requests
that touch `core/`, `tools/`, `scripts/`, the workflows and a few other paths.
Three jobs: *checks* (one version number everywhere with
`scripts/check_versions.py`, `ruff`, `webui/build.py --check`, the page's size
caps: `app.js` ≤ 256 KiB and `app.css` ≤ 64 KiB, shell syntax), *core* (all of
the above, with `bundle.py --max-kib 400`, and `apidoc.lua` compared with
`docs/api-v2.md`) and *oracle* (the bench suites, set up by
`.github/actions/bench`). `nightly.yml` (every night, every release tag, or by
hand) runs everything again plus the endurance run
(`core/spec/integration/endurance.py`, 10 minutes).

## Status

Released: 2.0.0 on 2026-09-27; this tree is 2.2.7 (`CHANGELOG.md`). 250 unit
specs; the bench suites and their counts are in `docs/21-architecture-2.0.md`
§14, the history of the phases and what was planned and never built in §15.
Spotify Connect / Deezer are the optional `streaming` module (ADR-0009, best
effort: bench-verified with a fake daemon, not against the services).

The bench on your machine: `tools/openjooki/tests` with `PLAYER_LUA=core` and
`CORE_BUILD=<repo>/build` (see `start_player.sh`).
