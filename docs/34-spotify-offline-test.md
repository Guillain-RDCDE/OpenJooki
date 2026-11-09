# Spotify offline test integration

The experimental `2.4.21-offline.N` application keeps the original Spotify
controller and adds separately authorized metadata and Premium offline playback.
Song lists support Free accounts through Web API OAuth; audio downloads require
verified Premium streaming credentials. The web page hides offline controls
without that Premium grant. See [the setup guide](../guide/spotify-offline.de.md).

A playlist uses `online` (original controller), `auto` (last complete snapshot,
otherwise original streaming) or `offline` (complete snapshot required). Without
an offline account, playback uses the original controller. Existing presets and
the vendor account are independent of this integration’s login/logout.

## MQTT contract

The existing v2 envelope, typed schemas and parent-code policy apply. Playlist
IDs are resolved against the local library. Commands never accept arbitrary
paths, audio keys or download addresses.

| Command | Payload | Behavior |
| --- | --- | --- |
| `spotify_offline.sync` | `{playlist: id}` | Deduplicate/enqueue sync, start when idle; select automatic mode. |
| `spotify_offline.cancel_queued` | `{playlist: id}` | Remove a waiting entry. |
| `spotify_offline.resume_queue` | `{}` | Continue after resolving storage/authentication trouble. |
| `spotify_offline.preview` | `{playlist: id, offset?: integer}` | Read metadata independently of downloads; up to 50 entries/page. |
| `spotify_offline.remove` | `{playlist: id}` | Remove snapshots when not in use or synchronizing. |
| `spotify_offline.mode` | `{playlist: id, mode: online/auto/offline}` | Persist mode independently of the original preset. |
| `spotify_offline.play` | `{playlist: id, index?: one-based integer}` | Play the exact saved global song index. |
| `spotify_offline.login` | `{mode?: metadata/premium}` | Request computer OAuth; a connected helper is required. |
| `spotify_offline.cancel_login` | `{}` | Invalidate the current request and staging directory. |
| `spotify_offline.auth_helper` | `{phase, request?, url?, error?}` | Helper heartbeat/status; completion must match the active request. |
| `spotify_offline.forget_account` | `{}` | Stop owned jobs, invalidate the grant and clear the queue. |

Mutation/authentication commands require the configured parent code. Preview and
normal transport are read/playback operations. V1 `OJ_OFFLINE_*` aliases project
this state as `spotifyOffline`. No credential or audio key is in public state.

The persistent queue has at most 32 waiting entries, binds to an account, restores
an interrupted active entry first and discards deleted/changed playlists. It
waits during active offline audio or account activation. Full storage and missing
authentication pause remaining entries until explicitly continued. Download errors
belong to their playlist; a failed playlist does not make the backend unavailable.

## Native file protocol and capacity

The SDK is pinned and exported as reviewed native/MIPS patches. Atomic JSON files
carry public catalog, progress, paged previews and acknowledged transport commands.
Public documents are bounded at 128 KiB; private indexes retain the complete order
(up to 2 MiB). Large lists are not truncated to the former artificial 500 songs.
Native Premium metadata checks the complete ordered URI list and revision before
and after sync. Missing/unsupported members fail explicitly; they are not skipped.
Only a fully checked generation replaces the previous complete snapshot.

Metadata-only OAuth uses the Web API and no librespot streaming session. Premium
login connects the session, checks its account type and caches reusable credentials.
The computer helper handles loopback OAuth, sends only public status via MQTT and
stages credentials via authenticated SSH. Logout/cancel invalidates the active
request before cleanup. A failed login retains the existing account. Account
changes cannot select another account’s cached audio. Logout removes grants and
retains private account-scoped audio on SD; it does not erase the vendor account.

The default `spotify_offline_quota_bytes = 0` derives capacity from actual free
space on the store filesystem. It reserves 128 MiB and checks temporary-write
space before each new track. A positive setting still imposes an explicit quota
with a 16 MiB reserve. Complete snapshots are never automatically evicted.

Offline playback uses only local files and cached account identity. Pause/resume,
next/previous, seek and stop use numbered acknowledged commands. Resume is saved
on state/track changes and every 15 seconds. A paused figure set to resume keeps
its existing player. The original online resume path saves on page pause as well
as token removal and preserves elapsed time across repeated metadata messages.

## Package and evidence

Packages contain paired Lua loader/core, web files, a static MIPS SDK and a SHA-256
manifest. Credentials, audio keys, music and private backups are excluded. The
physical test device runs the experimental application on p2; its prior p3 is
retained for rollback. Kernel/bootloader changes are outside this application.
The fork’s main branch and feature branch have been synchronized with upstream
`ed3c1ef` before the second candidate.

Verified before this update:

- Physical Jooki: all 18 songs freshly downloaded through the installed web button
  in 238.1 seconds, exact order, song selection and pause through normal controls.
- Isolated managed hardware sync: 18 exact songs (17 reused, one fetched), 82.4 s,
  peak RSS 5,612 KiB and no swap use.
- Managed hardware playback with the Internet route removed: play, pause, resume,
  next twice, seek, previous/restart and stop; original processes unchanged and
  networking restored. Audible prototype offline music confirmed by the user.
- Native metadata read: 710 music URIs, no truncation, complete native ordering.

New candidate checks:

- 422 Lua tests on the clean branch, including Free metadata routing, queue
  restore in both boot read orders, storage pause/restart, global song 700, stale login completion and resume.
- 68 SDK tests, formatting and Clippy with/without features; includes exact 710
  positions with bounded public pages, automatic capacity and metadata-only HTTP.
- Six computer-helper tests cover metadata-only grants, native Premium without
  Web API access, account mismatch, cancelled staging and secret-free status.
- Ten real-browser checks with a deterministic MQTT peer: pre-download titles,
  paging, escaping, exact song 52, queue/cancel, full storage, Free visibility,
  separate settings login/logout, mobile/desktop layout and no JavaScript errors.

These browser checks establish UI messages/visibility, not actual Spotify account
permissions. The real metadata-only check currently receives Spotify HTTP 429;
a successful real Free-account login/list read is still unverified. Do not hammer
the shared API client or interpret a rate limit as a Premium requirement.

Physical Jooki checks (2026-11-09):

- Actual browser reads 50 ordered titles before audio download, with all 710
  entries counted; next page carries positions 51–100. Native MIPS also read
  positions 701–710 under the configured 8 MiB data limit.
- Two real queue entries during offline audio; cancelling only the waiting
  selection and pausing starts the remaining 18-song refresh to completion.
- Original online “Anton Ritter”: page pause saved 92.562 seconds, another
  playlist played in between, and return resumed its chapter at 77.562 seconds
  (the intended 15-second rewind), rather than zero.
- Real logout deleted this backend’s grant and pending stage; late helper
  completion could not sign back in. Matching staged activation restored the
  same verified Premium account and complete snapshots. Cancelling a staged
  request retained the existing account. The original vendor account survived.
- Cold kernel reboot on .3 with two reject routes installed at S54, before Wi-Fi and
  application startup. Fresh boot reachable after 85.7 seconds; external TCP
  failed as unreachable and both reject routes remained during local playback,
  next, seek and pause. Internet restored and one-shot scripts removed; old p3
  untouched. No physical figure was present, so this proves the UI playback path
  after cold offline boot, with physical figure acceptance still separate.

## Remaining acceptance

Physical figure handling after restart, a real Free account, account-switch
OAuth in the browser and complete large-playlist downloads need device acceptance
before calling this a finished functional release. Resume switching between the
original online controller and the separate offline backend still needs explicit
acceptance; both keep their own persisted position. See also the
[feasibility audit](32-spotify-offline-audit.md) and
[earlier prototype evidence](33-spotify-offline-trial.md).

The .4 candidate fixes Spotify relinking: an available canonical track
can have an empty file map and provide its audio only through an alternative ID.
The new resolver keeps playlist URIs/order, selects a playable supplied alternative
and uses that track ID for the key. The first real item of the 710-song playlist
downloaded successfully on the computer and passed local decryption/seek checks.

The physical .4 trial downloaded the first two real tracks of “Anton Fuchs” and
reused the first file unchanged after an interruption. It then stopped at item
3/710 with `track_unavailable`. Independent native metadata checks for items 3
and 4 report no audio files and no alternatives. The test integration therefore
cannot publish a complete exact snapshot of this playlist as currently supplied;
it does not silently skip these positions. The .5 candidate marks these rows
in preview and reports the failed position explicitly. The selected 18-song
Krokodil snapshot remains complete and usable.

A paused SDK process was also found to inherit the core HTTP listener during a
soft application restart. The device launcher now closes inherited descriptors
before exec and explicitly uses the device’s BusyBox shell. A Linux regression
keeps the native child alive while rebinding the inherited port, including a
high-numbered descriptor. It runs in CI with the six computer-login checks.

Final candidate .5 includes the unavailable-row preview, explicit failed position,
and listener-isolation launch fix. The SDK build retains 68 passing tests and
both Clippy profiles, including daemon paths; core validation on the staged
branch has 422 passing specs plus the native launch regression.

A regression also covers partial cached audio: it still requests the complete
independent metadata page, instead of showing only the two downloaded entries.

The final .5 installed-browser check passes the unavailable markers, explicit
3/710 error, unchanged cached audio on retry and playback from the complete
Krokodil song list, without JavaScript errors. The paused-child application
restart leaves HTTP reachable. Both Internet routes and all one-shot boot files
were restored/removed after the offline experiment.
