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
its spec; the built bundle stays under 160 KiB.

## Run

```sh
lua5.1 core/spec/run.lua                                   # unit specs (no dependency)
lua5.1 core/spec/run.lua core/spec/integration/bus_spec.lua  # needs mosquitto on 127.0.0.1:1883
python3 tools/build/bundle.py                              # build/core.lua, core.min.lua, player.lib
python3 core/spec/integration/smoke.py                     # boots the built core against mosquitto
luacheck core                                              # lint (.luacheckrc at the repo root)
```

The bench distribution needs: `lua5.1 lua-socket lua-filesystem mosquitto
luacheck python3-paho-mqtt`. CI (`.github/workflows/ci.yml`) runs all of the
above on every push touching `core/`.

## Status

Phase 1 (kernel, adapters, api v2 skeleton, build, CI): done.
Phase 2 (library, tokens, playback, device, v1 compatibility): in progress.
