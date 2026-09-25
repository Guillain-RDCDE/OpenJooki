# New web page + application fixes (`patch webui`)

> **Since firmware 1.1.0 this is included in OpenJooki**: installing or updating
> from the phone installer page is enough. `patch webui` remains for a Jooki you
> manage from a computer, and `scripts/add-webui-to-image.py` applies the same
> changes to a firmware image.

The Jooki serves its own management page at `http://<jooki-ip>/`. The original
page (a 2018 React app by Muuselabs) still worked locally, but it had many bugs,
dead cloud features and trackers. The logic behind it (the Lua program inside
`/jooki/lib/player.lib`) had real data-loss bugs too. `patch webui` replaces the
page and fixes the program, through the same A/B mechanism as `harden`.

```sh
python3 tools/openjooki/jooki.py --host <ip> patch webui --dry-run   # build + check only
python3 tools/openjooki/jooki.py --host <ip> patch webui             # install (A/B, rollback armed)
python3 tools/openjooki/jooki.py --host <ip> patch switch <2|3>      # go back to the previous system
```

Your music, playlists and tokens are not touched (they live on the data
partition). A safety backup of the database is taken first anyway.

## How the Jooki works (short)

- `web_ctrl` (C, Mongoose) serves static files from `/jooki/app/www/public`
  (symlinked into `/tmp/web_ctrl_dirs/public` when the app starts) and receives
  uploads on `POST /upload` (multipart, field name = numeric upload id, stored as
  `uploads/upload_<id>`).
- The page talks to the application over **MQTT** (mosquitto, TCP 1883 and
  WebSocket 8000): it publishes JSON on `/j/web/input/<TYPE>` and receives the
  state on `/j/web/output/state` (full or partial) and errors on
  `/j/web/output/error`. See `docs/11-content-api.md`.
- The application is **Lua 5.1 source** stored in `player.lib`: zlib-compressed,
  with its first 2 bytes XOR-ed with its last 2 bytes (the `player` binary undoes
  that and loads it). `tools/openjooki/lua_patches.py` decodes it, applies
  targeted replacements — each must match exactly, otherwise nothing is applied —
  and re-encodes it. Only the fragments to change are in this repository; the
  original program is patched in place on your own Jooki and never distributed.
  The original is kept on the device as `player.lib.openjooki-orig`.

## Tokens: one rule

**A character is a character.** Every token of the same character (all black
dragons, all whales…) starts the same playlist. A token's name is only a label.

The original program silently switched a playlist to "this physical token only"
as soon as you named a token, so the other tokens of that character stopped
working. That is gone. Existing per-token links are converted to character links
at boot (if the character is free).

## Application fixes (Lua)

| Area | Before | After |
|---|---|---|
| Naming a token | "No update required" error on a second save; image wiped; the character's playlist moved to that single token | Idempotent, keeps the image, can clear a name, never touches links |
| Forgetting a token | Unlinked the character's playlist | Only forgets that token |
| Links | Per-token (`tagId`) links possible, no way to unlink | Character (`star`) links only, unique, `star:false` unlinks |
| "Unused tracks" (`TRASH`) | Could be renamed, linked, deleted, filled; stale; **removing a track deleted the file even if another playlist used it** | Read-only; always up to date and sorted; only really unused files are deleted |
| Failed upload | Could delete an existing file shared by other playlists, or leave a track without file | Never deletes an existing file; clean rollback; clear `UPLOAD_FAIL_TYPE` for non-audio files |
| Bad message | Any Lua error killed the player (music stops, unsaved state lost) | Every handler protected (`pcall`), invalid JSON rejected cleanly |
| Database writes | Write errors ignored, then the backup was rotated over a truncated file | Write errors detected, no rotation |
| Playlist delete | Its songs disappeared until reboot | They show up in "Unused tracks" immediately |
| Web radio | Same URL refused twice, id collisions, orphan entries | Validated URL, unique ids, orphans removed |
| Playback | Stale resume position made a token beep; empty playlist beeped | Falls back to track 1; empty playlist plays the "empty" sound |
| Misc | "Previous" ignored while paused; repeat/shuffle lost on crash; `.mp3` in titles; temp files left in RAM; stale partial uploads never cleaned; dead-cloud `curl` without timeout | Fixed |

## The new page

Plain HTML/CSS/JS served by the Jooki, no framework, no build step, **no external
request at all** (no Google Fonts, no analytics, no tracking pixel, no link to the
dead `jooki.rocks` domain). French or English (automatic, switchable).

- **Playlists**: create, rename (Enter/Escape), delete (with confirmation),
  play, choose the character (with a warning when it moves from another
  playlist), audiobook mode.
- **Tracks**: add files **from a phone or a computer** (file picker + drag and
  drop), from the library (search, multi-select), web radios; reorder by drag
  (mouse and touch), remove with undo; upload queue with progress, free-space
  check and clear error messages.
- **Library**: every song with the playlists it is in; "Unused" tab to add
  songs to a playlist or delete them from the Jooki (with confirmation).
- **Tokens**: one card per character, the playlist it starts (changeable), its
  tokens with optional nicknames, "forget" with confirmation, highlight of the
  token currently on the Jooki.
- **Player**: now playing, play/pause/previous/next, seek, volume,
  shuffle/repeat.
- **Settings**: battery, Wi-Fi, IP, storage, versions, limited volume (kids
  mode), language, turn off (with confirmation).
- Works on phones (bottom tabs) and computers (sidebar), light and dark mode,
  automatic reconnection, keyboard accessible.

The old page is kept on the device in `/jooki/app/www/public-openjooki-orig/`
(not served). A `service-worker.js` that unregisters itself replaces the old one.

## Tests

- **Bench** (off-device): the real decoded Lua program runs under Lua 5.1 with
  stubs for the 4 C functions, a real mosquitto, an emulation of `web_ctrl`, a
  fake audio engine, and Chromium (Playwright). 38 backend checks + 26
  end-to-end page checks, all green.
- **On the device** after install: file checksums, application answering over
  MQTT, page served, then non-destructive checks (migration, token rename,
  create/upload/reorder/delete a temporary playlist, "Unused tracks" protection,
  malformed messages without crash).

## Known limits (not changed here)

`web_ctrl` and mosquitto have no authentication. Any device on your Wi-Fi can
use the page (as before), and `web_ctrl` answers plain `GET` requests on
`/ll?action=` (root command, used by the OpenJooki installer) and
`/cmd/{poweroff,factory_reset,sdcard_format,…}`. A web page you visit could
therefore send such requests to the Jooki if your browser lets public sites
reach local addresses (recent Chrome asks for permission first). Closing this
means changing how the phone installer talks to the Jooki; it is tracked as a
separate decision.
