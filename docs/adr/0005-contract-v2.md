# ADR-0005 — A versioned contract with revisioned state and typed errors; v1 kept for one release

Status: proposed (2026-09-26)

## Context
The page and the Jooki talk over MQTT with ~40 message types inherited from
the 2018 app: free-text errors, a state document published whole or by
sub-tree with no ordering information, and a position update every second to
everyone. Community tools (Home Assistant integrations) use the same topics.

## Decision
- v2 messages carry `v`, a client `id`, a `type` and a `payload`; replies
  carry `ok` and a typed `error {code, field, message}` from a closed list.
- The state carries a monotonically increasing `rev`; partial updates are
  patches with the new `rev`; a client that misses a revision asks for a full
  state. Position is a separate light message, sent only while a page is
  connected.
- Every message has a JSON Schema in `docs/api/v2/`; the api module validates
  inbound messages against it; the bench uses the same schemas.
- v1 topics are served by a translation table for one major release, then
  removed with notice in the CHANGELOG.

## Alternatives
- **Keep v1 only**: no breaking change, but no way to fix ordering, errors or
  traffic without breaking it anyway.
- **HTTP/JSON API instead of MQTT**: `web_ctrl` is closed; we would need our
  own HTTP server in Lua (possible, ~400 lines) — considered for 3.0 with the
  security model, not needed now.

## Consequences
- Contract tests become part of CI; a schema change without a test fails.
- The 1.x page keeps working on 2.0; the v2 page client is a separate,
  smaller change.
