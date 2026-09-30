# ADR-0011 — Put the core in its own file; player.lib becomes a loader

Status: accepted (2026-09-30, decision of the maintainer: "double the room, what are the stakes")

## Context
The closed C host (`/jooki/bin/player`) decompresses `player.lib` into a fixed
200 KiB buffer and runs it as a Lua 5.1 chunk (ADR-0001). Until now the whole
core *was* `player.lib`, so the core inherited that 200 KiB ceiling. ADR-0010
had already raised our own budget to 192 KiB and, at 2.0.9, the core reached
191.9 KiB: the budget was full and the next feature — our own web server to
close `/ll` and `/cmd` (ADR-0007) — could not fit. The host's limit cannot be
changed (it is inside the closed binary), so more room could only come from
somewhere other than `player.lib`.

## Decision
`player.lib` becomes a small **loader** (under 1 KiB). The C host still
decompresses and runs it, well within the 200 KiB buffer. The loader reads the
real core from **`/jooki/lib/core.lua`** — a plain file next to it on the same
A/B system partition — checks its byte length against a value baked in at build
time, `loadstring`s it and runs it. The core therefore has no 200 KiB ceiling
any more: its only limit is memory (the 4 MB RSS budget), and the build guards
it at 400 KiB (`bundle.py --max-kib`, default 512).

`tools/build/bundle.py` now writes `build/core.min.lua` (the core, shipped as
`/jooki/lib/core.lua`) and `build/player.lib` (the loader, carrying the version
and the core's exact length). The installer (`jooki.py`, via `core_side_files`)
and the image builder (`add-webui-to-image.py`) place both files together, on
the spare partition, verified by md5 before the A/B switch — so a rollback
restores the matching pair, and a partial write is caught before boot.

## Alternatives
- **Drop the v1 compatibility layer now** (17 KiB back, planned for 2.1
  anyway): real room, but bounded and one-off, and it does not change the
  ceiling — the next large feature would hit it again. Kept as a later,
  separate cleanup, not as the answer to headroom.
- **Ship our own C host** (ADR-0001's open door): full control and no buffer at
  all, but a cross-compiler to maintain and a much bigger change to the image.
  Not needed: a one-KiB Lua loader gives the room with none of that cost.
- **Compress the core on disk and inflate in the loader**: the device has zlib
  through the core, not the loader, and disk is not scarce. Plain text on disk
  is simpler and stays readable for debugging.

## Consequences
- The core can grow to roughly double before the 400 KiB guard, and that guard
  can be raised further with a one-line change, never blocked by the host again.
- One more file to install and verify per release; both paths already md5-check
  every file they write, so the loader + core are verified as a pair.
- The bench is unchanged: it loads `build/core.lua` (readable) directly through
  `harness.lua`. The device boot path — loader reads `core.lua` from disk — is
  covered by `tools/openjooki/tests/test_loader.py` (boot to READY, plus the
  wrong-size and missing-file guards) in CI.
- ADR-0010's 192 KiB budget no longer binds the core; it stands only as the
  history of why the room ran out.
