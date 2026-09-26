# ADR-0006 — Third-party code: minimal, vendored, pinned

Status: proposed (2026-09-26)

## Context
The old program embeds 1 423 lines of third-party Lua (JSON.lua, an old Paho
MQTT client, sha1): 26 % of its size, in a 200 KiB budget. Nothing can be
installed on the device at runtime; everything ships inside `player.lib`.

## Decision
- **JSON**: vendor `rxi/json.lua` (MIT, ~400 lines, fast), with a 30-line
  wrapper for pretty output and `null` handling; tested against our files.
- **MQTT**: an in-house minimal 3.1.1 client (~300 lines): connect, subscribe,
  publish QoS 0, keep-alive, reconnect with backoff; tested against mosquitto
  on the bench. No QoS 1/2, no TLS (localhost only).
- **No SHA-1**, no base64 library (not needed once dead services are gone);
  md5 for track ids implemented in Lua (~120 lines) and tested against
  `md5sum`.
- Every vendored file has its licence header and a `VENDOR.md` line with the
  upstream version; updates are explicit commits.

## Alternatives
- **Keep Paho Lua**: EPL licence (compatible), but 556 lines, busy-wait
  utilities and an API built around callbacks; would need wrapping anyway.
- **A schema library**: too big; our validator is ~120 lines for the subset
  we use (types, required, enum, ranges, string patterns).

## Consequences
- Total third-party code ≈ 450 lines (vs 1 423).
- Two small components (MQTT client, md5) are ours to test thoroughly; their
  specs run against real tools in CI.
