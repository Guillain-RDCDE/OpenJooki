# ADR-0012 — Retire the 1.x patched program and its tooling

Status: accepted (2026-10-03, decision of the maintainer during the refactoring pass)

## Context
ADR-0002 replaced the 1.x approach (49 exact text replacements inside Muuselabs'
minified program, `tools/openjooki/lua_patches.py`) with our own core, and kept the
patch list "maintained until 2.0 is the default". 2.0.0 shipped on 2026-09-27; the
Jooki in the maintainer's family and the installs announced on Reddit are on 2.2.x.
The 1.x path still weighed on the repository: 1 271 lines of patches, a bench mode
(`run.lua`, `webctrl_emu.py`, `prepare.py`, `unit_bedtime.py`) that CI never ran, two
`jooki.py` commands that only made sense before the page existed (`playlist`, `music
add`, and both broken since 2.1 bound the broker to localhost), two A/B patches of the
factory system (`cut-cloud`, `harden`) that the 2.x image makes moot, and `patch
webui` building the patched program whenever `--core` was omitted.

## Decision
- `lua_patches.py`, `patches/`, the 1.x bench files and the `playlist` / `music` /
  `cut-cloud` / `harden` commands are removed. The only thing kept from `lua_patches.py`
  is the codec of the `player.lib` container, now `tools/openjooki/playerlib.py`, shared
  by the build, the device tool, the release image script and the loader test.
- `jooki.py patch webui` and `scripts/add-webui-to-image.py` require `--core`.
- The bench runs the core only (`PLAYER_LUA` defaults to `core`).

## Consequences
- A Jooki still on 1.x updates like any other: from its page (the OTA fetches the
  current image), by the phone path (`b.sh`), or by a new card. It can no longer be
  re-patched to 1.x by `jooki.py`; the 1.x releases stay downloadable on GitHub.
- The original program is still read and kept on the device (`player.lib.openjooki-orig`,
  ADR-0004): reversibility to the factory program is unchanged.
- docs/10, docs/18 and docs/22 describe the 1.x mechanism as history.
