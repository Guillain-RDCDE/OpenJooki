# Spotify offline test version

This experimental application adds an optional Premium offline backend alongside
unchanged original Spotify streaming. A playlist can use `online` (original
controller), `auto` (last complete offline snapshot when present; otherwise
original streaming) or `offline` (require a complete local snapshot).

## API contract

Commands use the existing v2 MQTT command/reply envelope and parent-code policy.
All playlist identifiers are resolved against the local library; commands do not
accept arbitrary filesystem paths or download addresses.

| Command | Payload | Result |
| --- | --- | --- |
| `spotify_offline.sync` | `{playlist: id}` | Start/resume one synchronization job; retain the previous complete snapshot. |
| `spotify_offline.remove` | `{playlist: id}` | Remove this playlist's offline snapshots when not playing/synchronizing. |
| `spotify_offline.mode` | `{playlist: id, mode: "online" or "auto" or "offline"}` | Persist the playback selection independently of the original preset. |
| `spotify_offline.play` | `{playlist: id, index?: one-based number}` | Start a saved playlist/track through the regular playback state machine. |
| `spotify_offline.forget_account` | `{}` | Stop managed jobs/playback and invalidate this backend's authentication. |

`sync`, `remove`, `mode` and `forget_account` require the parent code when one is
configured. Existing transport commands control offline playback too.

Public `state.spotify_offline` contains availability, account readiness (no
credentials), storage bytes, per-playlist snapshots with ordered public song
metadata, playback mode, synchronization progress and an error code. The v1 UI
projection exposes the same data as `spotifyOffline` and provides `OJ_OFFLINE_*`
compatibility commands. Download progress counts completed tracks against the
resolved playlist total; incomplete snapshots never become playable.

## Native process contract

Managed player commands publish atomic JSON status files. Core-to-player
controls are a bounded queue of numbered commands in an atomic JSON file;
acknowledgments discard processed commands. Processes run only while refreshing
metadata, synchronizing or playing, so the SDK does not stay resident when idle.
Downloaded generations are private, account-scoped and committed only after all
ordered members have passed integrity checks. A failed update retains the last
complete generation. Keys and authentication files are never in public status.

The test package includes the Lua application, web UI, static MIPS player and a
SHA-256 deployment manifest. Authentication is provisioned separately; credentials and music are
excluded from the package. The original streaming backend and presets remain
available. Premium is required for this experimental backend.

## Candidate validation (2026-11-08)

- Core: 385 unit/integration checks, including offline routing, parent permissions,
  acknowledged controls, stale process/job replies and startup failures.
- SDK: 59 full-feature tests, formatting and Clippy with/without features.
- Browser bundle with a deterministic MQTT peer: download command, progress,
  ordered song metadata, exact song index, storage errors, account invalidation,
  original mode, disabled backend, mobile/desktop layout; no browser errors.
- Physical Jooki: managed sync publishes all 18 selected songs in exact order.
  Seventeen verified prior downloads were reused and one was fetched again;
  completion took 82.4 seconds. Peak RSS 5,612 KiB; no swap.
- Physical Jooki with its Internet route removed: managed play, pause, resume,
  two next commands, seek, restart/previous and stop. Original service processes
  were unchanged and the route was restored with traps/watchdog protection.
- Package manifest and read-only device preflight match existing OpenJooki 2.4.21.
  The running application has not yet been replaced.

The browser peer check verifies the UI/messages; it is separate from the native
hardware checks and does not establish the complete installed UI-to-device path.

## Acceptance still required

Web-triggered synchronization, visible songs/progress/storage, transport and
figure controls, an offline cold restart, interrupted downloads, full storage,
account changes and sustained audio playback must pass before this is a
functional test release. See the completed SDK/hardware findings in
[the trial report](33-spotify-offline-trial.md).
