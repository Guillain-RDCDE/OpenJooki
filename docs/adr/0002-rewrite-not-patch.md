# ADR-0002 — Rewrite the application from scratch instead of patching it further

Status: proposed (2026-09-26)

## Context
1.0–1.3 change Muuselabs' minified program with 49 exact text replacements
(`tools/openjooki/lua_patches.py`). It is tested and it ships, but every
feature depends on fragments of code we do not own, cannot publish, and
cannot restructure (docs/22 §7 lists the structural defects: shell-outs in
the loop, memory-only playback state, untyped errors, closures everywhere).

## Decision
Write a new application (`core/`) with our own modules, tests and contract,
and switch to it through the A/B mechanism once it passes the same
integration checks as the patched program. Keep the patched program on the
spare partition for one release.

## Alternatives
- **Continue patching**: cheapest per feature, but the cost grows with every
  feature and the program can never be distributed or reviewed as a whole.
- **Partial rewrite (replace modules one by one inside the old program)**: the
  old program's globals and closures make module boundaries unreliable; the
  test bench would have to run two half-programs. Rejected.

## Consequences
- Phases 1–3 of docs/21 §15 are a real investment before any visible gain.
- The bench and its 179 checks become the oracle; they must be ported to the
  v2 contract first (through the v1 compatibility layer they run unchanged).
- The original program is still needed by 1.x users; `lua_patches.py` stays
  maintained until 2.0 is the default.
