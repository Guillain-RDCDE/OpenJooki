# OpenJooki core (2.0)

The Jooki's application, written from scratch: readable Lua 5.1 modules, built
into the format the Jooki's C host loads. Design: `docs/21-architecture-2.0.md`;
what it replaces: `docs/22-core-inventory.md`; decisions: `docs/adr/`.

```
kernel/     loop, dispatch, timers, state, commands, log, config   (no I/O)
adapters/   bus (MQTT), files (atomic JSON), clock, host (C functions), shell (named actions)
api/        the contract with the page: v2 (schema-validated), v1 compatibility
services/   library · playback · tokens · bedtime · device · network · update · streaming
fakes/      in-memory adapters for the specs and the simulator
vendor/     third-party code (json.lua, MIT), pinned
spec/       unit specs (*_spec.lua) and integration (spec/integration/)
main.lua    wiring only
```

Rules (enforced by review and CI): a service never requires an adapter; a
handler is `(doc, event) -> { state = {...}, commands = {...} }` and does no
I/O; every side effect is a command executed by the kernel; every module has
its spec; the built bundle stays under 176 KiB (`bundle.py --without
services.streaming` builds a lean core without Spotify/Deezer, ADR-0009).

## Run

```sh
lua5.1 core/spec/run.lua                                   # unit specs (no dependency)
lua5.1 core/spec/run.lua core/spec/integration/bus_spec.lua  # needs mosquitto on 127.0.0.1:1883
python3 tools/build/bundle.py                              # build/core.lua, core.min.lua, player.lib
python3 core/spec/integration/smoke.py                     # boots the built core against mosquitto
luacheck core                                              # lint (.luacheckrc at the repo root)
lua5.1 tools/build/apidoc.lua > docs/api-v2.md             # the v2 contract, generated from the code
```

The bench distribution needs: `lua5.1 lua-socket lua-filesystem mosquitto
luacheck` and `paho-mqtt>=2` (pip; the Ubuntu package is 1.x). CI (`.github/workflows/ci.yml`) runs all of the
above on every push touching `core/`.

## Status (docs/21 §15)

- Phase 1 (kernel, adapters, api v2, build, CI): done.
- Phase 2 (library, tokens, playback, device, uploads, v1 compatibility): done —
  the 38 backend checks of the 1.x bench pass unchanged on the new core.
- Phase 3 (bedtime, update, network + mDNS): done — 24 bedtime, 13 network and
  47 page checks of the 1.x bench pass unchanged; 134 unit specs; endurance run
  (`core/spec/integration/endurance.py`) in CI for 3 minutes, nightly for longer.
  Spotify Connect / Deezer ported as the optional `streaming` module (ADR-0009,
  best effort: bench-verified with a fake daemon, not against the services).
- Phase 4 (Wi-Fi manager, Bluetooth rescue, security) → 2.1.
- Phase 5 (a real Jooki: A/B install, 24 h, rollback): next.

Oracle on your machine: `tools/openjooki/tests` with `PLAYER_LUA=core` and
`CORE_BUILD=<repo>/build` (see `start_player.sh`).
