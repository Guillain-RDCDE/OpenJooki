# ADR-0010 — Raise the stripped size budget from 176 to 192 KiB

Status: accepted (2026-09-28, decision of the maintainer with the airplane mode)

## Context
The host decompresses the program into a fixed 200 KiB buffer (ADR-0001); the
build refuses anything at or above it. Our own budget sat at 176 KiB since
ADR-0009 (160 before), leaving 24 KiB for the v1 compatibility layer, which
was to leave in 2.1. Releases 2.0.2 to 2.0.4 (security switches, parent code,
maintenance SSH, third-party NFC tags, tag photos) brought the bundle to
173 KiB, and the airplane mode from the page (bounded, with its boot restore)
to 175.6 KiB: a hundredth of the budget was left, and the next fix would
have failed the build for a reason unrelated to its content.

## Decision
The budget becomes **192 KiB** stripped (`bundle.py --max-kib 192`, the CI
build step, docs/21). The host's hard limit stays 200 KiB and stays enforced
by the build and by the installer (`load_core`).

Alternatives considered: making room by dropping the v1 layer now (14 KiB) —
rejected, the 1.x page still talks v1 and the 2.1 plan keeps it one release
longer; shrinking code by hand — rejected, readability is the point of the
rewrite (docs/21 size targets).

## Consequences
- 8 KiB stay between the budget and the host's limit, for the v1 layer's last
  release and for the small fixes of the 2.0 line.
- The v1 layer leaving in 2.1 gives the room back; the budget may then go
  down again, by a new record.
- The lean build (`--without services.streaming`) is unaffected (165 KiB).
- **State at 2.0.9 (2026-09-29): 191.9 KiB, the budget is full.** Spotify from the
  phone, the Wi-Fi watchdog and the broker keeper took the rest. The next feature needs a
  decision first: the v1 layer leaving (14 KiB back), or a new ADR raising the budget
  towards the host's 200 KiB.
