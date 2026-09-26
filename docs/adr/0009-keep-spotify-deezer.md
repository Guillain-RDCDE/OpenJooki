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
- About 250 readable lines (11 KiB stripped) more; the size budget goes from
  160 to 176 KiB (the v1 compatibility layer, 14 KiB, leaves in 2.1). A lean
  build without the module: `bundle.py --without services.streaming`;
  `main.lua` and the v1 layer tolerate its absence.
- Ported: login/logout/active, now-playing and transport (pause, continue,
  next, previous, seek, skip), presets (`spotify.new_playlist` creates the
  playlist from what is playing), shuffle/repeat/volume forwarded to the
  active service, Deezer login/options/playlists/credentials.
- Not ported: the Deezer daemon restart (`deezer_ctrl` is not on the 2022
  firmware) — `deezer.set_config` writes the credentials and logs a warning.
- Playlist records keep their `spotify`/`deezer` fields; the library ignores
  them except to hand them to `streaming`.
