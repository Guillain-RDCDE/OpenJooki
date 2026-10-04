# The web page (and, in 1.x, the fixes of the original program)

> The page is what every OpenJooki serves at `http://jooki.local/`; its code is
> `tools/openjooki/webui/` (the script is edited in `src/`, one file per subject, and put end to end
> into `app.js` by `build.py`). The "application fixes" below are **history (1.x)**: since 2.0
> the behaviour lives in our own core (`core/`, [21-architecture-2.0.md](21-architecture-2.0.md)),
> and `jooki.py patch webui --core` / `scripts/add-webui-to-image.py --core` install that core
> with the page ([ADR-0012](adr/0012-retire-1x.md)).

The Jooki serves its own management page at `http://<jooki-ip>/`. The original
page (a 2018 React app by Muuselabs) still worked locally, but it had many bugs,
dead cloud features and trackers. The logic behind it (the Lua program inside
`/jooki/lib/player.lib`) had real data-loss bugs too. In 1.x, `patch webui` replaced
the page and fixed that program in place; since 2.0 it installs the page with our own
core, through the same A/B mechanism, and is refused without `--core`:

```sh
python3 tools/build/bundle.py                                                       # the core, into build/
python3 tools/openjooki/jooki.py --host <ip> patch webui --core build/player.lib --dry-run   # build + check only
python3 tools/openjooki/jooki.py --host <ip> patch webui --core build/player.lib    # install (A/B, rollback armed)
python3 tools/openjooki/jooki.py --host <ip> patch switch <2|3>                     # go back to the previous system
```

Your music, playlists and tokens are not touched (they live on the data
partition). A safety backup of the database is taken first anyway.

## How the Jooki works (short)

Today (2.1 and later):

- The core's own web server (`core/adapters/httpd.lua`, port 80) serves the page's
  files from `/tmp/web_ctrl_dirs/public` (links to `/jooki/app/www/public`, rebuilt at
  every start) and receives uploads on `POST /upload` (multipart, field name = numeric
  upload id, stored as `uploads/upload_<id>`). Nothing else: no `/ll`, no `/cmd`.
- The page talks to the core over **MQTT** on the WebSocket (mosquitto, port 8000,
  with the per-Jooki password it reads at `/oj-auth.json`): it publishes JSON on
  `/j/web/input/<TYPE>` and receives the state on `/j/web/output/state` (full or
  partial) and errors on `/j/web/output/error`. See `docs/11-content-api.md`.
- The application is our core, `/jooki/lib/core.lua`; `player.lib` is a small loader
  for it (ADR-0011). `player.lib` is zlib-compressed, with its first 2 bytes XOR-ed
  with its last 2 bytes (the `player` binary undoes that and loads it);
  `tools/openjooki/playerlib.py` is the codec.

In 1.x (history): the closed `web_ctrl` (C, Mongoose) served those files and
`/upload`, and the application was Muuselabs' Lua program inside `player.lib`.
A tool, `lua_patches.py` (gone with ADR-0012), decoded it, applied targeted
replacements — each had to match exactly, otherwise nothing was applied — and
re-encoded it; the original program was patched in place on each Jooki and never
distributed. It is still kept on the device as `player.lib.openjooki-orig`.

## Tokens: one rule

**A character is a character.** Every token of the same character (all black
dragons, all whales…) starts the same playlist. A token's name is only a label.

The original program silently switched a playlist to "this physical token only"
as soon as you named a token, so the other tokens of that character stopped
working. That is gone. Existing per-token links are converted to character links
at boot (if the character is free).

## Application fixes (Lua) — history (1.x)

What the 1.x patches changed in the original program. The core written for 2.0
behaves like the "After" column from the start.

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

Plain HTML/CSS/JS served by the Jooki, no framework, no bundler and no minifier
(`webui/build.py` only puts the files of `webui/src/` end to end into `app.js`, and CI
checks that `app.js` is what `src/` gives), **no external
request at all** (no Google Fonts, no analytics, no tracking pixel, no link to the
dead `jooki.rocks` domain). English by default; French or Dutch when the browser is set to that language (switchable in Settings).

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
  token currently on the Jooki. Since 2.2 every flat token (and every foreign
  NFC tag) is a character of its own, with a picture chosen in a library of 659
  ready-made pictures, or a photo ([23-nfc-tags.md](23-nfc-tags.md) §4-§5).
- **Player**: now playing, play/pause/previous/next, seek, volume,
  shuffle/repeat.
- **Settings**: battery, Wi-Fi, IP, storage, versions, limited volume (kids
  mode), language, turn off (with confirmation). Since OpenJooki 2: airplane
  mode for a chosen time (Wi-Fi and Bluetooth off; the Jooki brings them back
  by itself, and at its next start in any case — [24-hardware-and-lights.md](24-hardware-and-lights.md)).
  Since 2.2 the Settings page is short: a "My Jooki" card (name, battery,
  storage, version) and grouped rows that show their value; each topic opens on
  a page of its own, `#/settings/<topic>` (`bluetooth`, `night`, `airplane`,
  `wifi`, `update`, `language`, `theme`, `mp3`, `parent`, `home`, `maintenance`),
  with the back button of the top bar.
- **Updates** (since 1.2.0): Settings shows the installed OpenJooki version and
  checks GitHub for a newer release (also once when the page opens). If there
  is one, a banner appears on the home page and **Update now** installs it from
  the page, with progress; the page reconnects after the restart and confirms
  the new version.
- Works on phones (bottom tabs) and computers (sidebar), light and dark mode,
  automatic reconnection, keyboard accessible.

The old page is kept on the device in `/jooki/app/www/public-openjooki-orig/`
(not served). The old page's service worker is not replaced by a file any more: the
page unregisters any service worker it finds when it starts (`src/23-boot.js`).

What a render asks again and again (the user's playlists sorted by title, the playlist
each character starts) is derived from the state once and kept in an index
(`src/04-state.js`, `index()`), dropped whenever the library part of the state or the
language changes.

## Updating from the page

Two messages added to the application (each answers at once and does the work in
the background, so the player never waits on the network):

| Message | What the Jooki does | What the page reads |
|---|---|---|
| `/j/web/input/OJ_UPDATE_CHECK` | writes `{"pending":true}`, then downloads the manifest at `update_manifest_url` (by default `version.json` of the latest GitHub release; `{"error":"offline"}` if it can't) | `/oj-latest.json` |
| `/j/web/input/OJ_UPDATE_START` | downloads the script at `update_script_url` (by default `o.sh` on GitHub Pages, the same as the phone installer's) and runs it, once at a time | `/oj-status.txt` (the installer's log) |

The two addresses are keys of the core's configuration (`core/kernel/config.lua`), and
the shell actions that fetch them (`core/adapters/shell.lua`, `is_update_url`) accept
only our GitHub (`https://github.com/Guillain-RDCDE/OpenJooki/…`,
`https://guillain-rdcde.github.io/OpenJooki/…`) or `http://127.0.0.1:<port>/…`, which
is how the bench serves its own. The same two actions answer the v2 commands
`update.check` and `update.start`.

The installed version comes from `/etc/openjooki-version` and is sent in the
state as `device.openjooki`. The install itself is unchanged: spare partition,
sha256 check, rollback armed.

The update screen (`src/17-update.js`) reads `/oj-status.txt` every 3 s. While an
update runs, every 10 s it also checks that the connection is alive (`checkAlive` in
`src/05-connection.js`: it asks for the state and reconnects when nothing answers
within 5 s; also when the page comes back in front) and draws the screen again; when
nothing has moved for 3 minutes it says what to do. The browser that started an update
remembers it (`localStorage`, key `oj.upd`, for an hour), so a reloaded page takes the
update up where it is.

## Tests

- **Bench** (off-device, `tools/openjooki/tests/`): the built core runs under Lua 5.1 with
  stubs for the 4 C functions, a real mosquitto, a fake audio engine and Chromium
  (Playwright): 48 backend checks, 83 end-to-end page checks and the other suites
  ([21-architecture-2.0.md](21-architecture-2.0.md) §14), in CI.
- **On the device** after install: file checksums, application answering over
  MQTT, page served, then non-destructive checks (migration, token rename,
  create/upload/reorder/delete a temporary playlist, "Unused tracks" protection,
  malformed messages without crash).

## Security

Since 2.1.0 the core serves the page itself and `web_ctrl` (with its root `/ll` and `/cmd`)
is no longer started; the broker listens on localhost, the page's WebSocket needs the
per-Jooki password, and a parent code can guard the changes: [ADR-0007](adr/0007-security-model.md).
