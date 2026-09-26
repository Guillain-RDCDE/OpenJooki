# ADR-0009 — Keep Spotify Connect and Deezer as an optional module

Status: accepted (2026-09-26, decision of the maintainer)

## Context
The old program has about 350 lines of Spotify Connect and Deezer glue: the
closed `spotify_ctrl` daemon does the streaming, the application handles
login state, presets stored in playlists, and playback events on separate
topics. The maintainer's family does not use them and we have no account to
test with, but the daemon is still on every Jooki and other families may use
it. The proposal was to drop them; the maintainer decided to keep them.

## Decision
Port the Spotify and Deezer message paths into one optional module,
`services/streaming`, with these rules:
- it owns only its own state (`spotify`, `deezer` sub-trees) and the
  streaming variants of the playback transitions;
- it is **isolated**: any error inside it is caught and logged; local
  playback, tokens and bedtime never depend on it;
- it can be disabled by configuration (default: enabled);
- it is marked "best effort" in the docs: ported as observed in the old
  program (docs/22), verified on the bench with a fake `spotify_ctrl`, not
  verified against Spotify's servers.

Jooki Play, the cloud heartbeat and the Mender client stay dropped: their
servers are gone and Jooki Play embeds a dead API key.

## Consequences
- About 400 readable lines more and one more fake daemon on the bench.
- Playlist records keep their `spotify`/`deezer` fields; the library ignores
  them except to hand them to `streaming`.
