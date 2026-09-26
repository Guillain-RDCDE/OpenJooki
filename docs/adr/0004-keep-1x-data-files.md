# ADR-0004 — Keep the 1.x data files and formats (reversibility)

Status: proposed (2026-09-26)

## Context
The family's library lives in `/jooki/external/jooki/` as JSON files
(`playlists.json`, `tracks.json`, `tokens.json`, `audiocfg.json`,
`bedtime.json`, `resume.json`) plus the audio files named by track id (first
16 hex of the file's md5). Firmware updates never touch that partition. Both
1.x and 2.0 will exist on the same Jooki (A/B) for at least one release.

## Decision
2.0 reads and writes the same files, in the same place, with the same ids.
Where a field must change, `_.version` is bumped and a migration function
converts on load; fields 1.x needs are kept so that a rollback to 1.x still
reads the files.

## Alternatives
- **A new store (SQLite, a single file)**: cleaner queries, but SQLite is not
  on the device, and a rollback would lose changes made under 2.0.
- **New file names with a one-way migration**: simpler code, but no way back.

## Consequences
- The library module carries a compatibility burden (legacy `tagId`, `plType`,
  Spotify/Deezer fields ignored but preserved).
- Writes stay "whole file" (fine at this size; `tracks.json` for 1 000 tracks
  is ~300 KB, written at most once a second when dirty).
- Atomic write (tmp → fsync → rename → .bak) and a checksum line become the
  rule for every file.
