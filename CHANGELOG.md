# OpenJooki — Changelog

## OpenJooki 2.0.8 (29 September 2026) — a safer start
- **The Jooki gets its Wi-Fi back by itself.** Its Wi-Fi chip can stay stuck on
  "connecting" and nothing on the original system woke it up again: the Jooki stayed
  out of reach until someone restarted it. Now, after ten minutes without Wi-Fi, on the
  charger and with nothing playing, the Jooki restarts itself, silently. Twice at most
  in a row: if the Wi-Fi is really gone (moved house, new box), the Bluetooth page is
  the way. Never in airplane mode, never during an update.
- **No more factory network.** At every start, the original system gave the Wi-Fi chip
  Muuselabs' own factory network again, a network no home has, and the chip wasted its
  tries on it. It is no longer added, and it is removed when the chip knows your
  network. The chip also gets 30 seconds to start instead of 10, and a slow start no
  longer leaves a "factory mode" mark behind for good.
- **The Jooki's message hub keeps running.** Tokens, knobs and the page all go through
  one small program on the Jooki (the broker). Nothing restarted it if it stopped: the
  Jooki went deaf. The Jooki now starts it again by itself, and no longer burns its
  processor (and battery) while it waits for it.
- **A card that cannot change the Jooki's security.** A settings file dropped on the SD
  card's computer-readable part used to replace the Jooki's own message-hub settings,
  password included. It is ignored now.
- For the tinkerers: the maintenance access (Settings, one hour) takes an SSH public
  key, kept on the Jooki across updates (updates used to wipe it). Only while the
  access is open, and behind the parent code when one is set.

## OpenJooki 2.0.7 (29 September 2026) — a character for your Spotify playlist
- **Spotify connects again after a restart.** After some restarts, the phone saw the
  Jooki in its list of devices but could not connect to it. The Jooki told Spotify
  "no network" once while starting, before its Wi-Fi was up, and never said it again.
  It now tells Spotify every time the Wi-Fi changes, as the original program did.
  Found on a family Jooki after the 2.0.6 update, and checked on it.
- **Put your Spotify music on a character.** While Spotify plays on the Jooki, open
  the player at the bottom of the page and tap *Put on a character*: pick a name and
  a character. Then the character plays that Spotify playlist, even without the
  phone; taking it off pauses it. The Muuselabs app had this; OpenJooki's page did
  not. The Spotify account must stay connected to the Jooki.
- **Who sings it.** Under a Spotify song the page now shows the artist and the album
  ("Albin de la Simone / Happy End"), where it showed only the album.
- **Settings on a big screen.** On a wide screen the page background stopped halfway
  down long pages such as Settings. It now goes to the bottom.

## OpenJooki 2.0.6 (29 September 2026) — Spotify from the phone
- **Spotify still works on the Jooki.** Pick the Jooki in the Spotify app on your
  phone (the devices button): the music comes out of the Jooki. Checked on a family
  Jooki on 29 September 2026.
- **The page now shows it.** While Spotify plays, the page shows the song, the artist
  and where it plays from, instead of "Nothing playing", and its pause and play
  buttons work.
- **One sound at a time.** Put a token on while Spotify plays: Spotify pauses and the
  token plays alone. Press play on the phone again: Spotify takes over and the
  token's music stops. Before, both played at once. Taking a token off does not
  pause Spotify started from the phone; the sleep timer does.
- **Headphones.** Plug headphones in while Spotify plays: the sound goes to the
  headphones, as it did before OpenJooki.
- Checked on the bench with a stand-in for the Spotify program, in both orders its
  messages can come in (`tools/openjooki/tests/test_spotify.py`, in CI).
- **The page is never out of date.** After an update, a phone could keep showing the
  old page (Settings said "OpenJooki 2.0.5, page 2.0.4", and the new settings were
  missing). Now the page sees it and loads itself again, once, on its own.

## SD card tools (29 September 2026) — back to the original Jooki
- **The original Jooki, on a card.** The SD card tool (Windows, Mac, Linux) has a third
  choice, *The original Jooki: back to the program it was sold with*: a complete card with
  Muuselabs' own program of December 2022, without OpenJooki and without anyone's music. For
  whoever wants a Jooki back exactly as it was sold. The Jooki's own card stays the way back.
  Honest note shown in the tool: the official app and Jooki's servers are gone, so the
  original program can no longer be set up from a phone.
- It is rebuilt from an OpenJooki image, which keeps every file it replaced
  (`tools/sdcard/make_original_rootfs.py`), then checked against a Jooki backed up before
  OpenJooki: every system file identical, nothing extra. It lives in its own GitHub release,
  `original`. Not yet started in a real Jooki. Details in docs/27.

## OpenJooki 2.0.5 (29 September 2026) — Bluetooth speakers, airplane mode, Wi-Fi without the app
- **Airplane mode, the way parents asked for it, without the trap.** Settings →
  *Airplane mode* switches the Jooki's Wi-Fi and Bluetooth off (no radio next to
  the bed, or on a plane). You choose for how long: a few hours, until the morning
  (the end of night mode), or until the Jooki is switched off and on again. The
  Jooki switches them back on by itself at that time, and in every case its next
  start brings the Wi-Fi back: a tap on the page can never leave a Jooki with its
  two side dots orange for good, which the knob gesture can (the chip remembers
  it across restarts, and the way back is a trick few owners know).
- **The page says what is going on.** While the Jooki is in airplane mode the page
  cannot reach it, on purpose. Instead of "the Jooki is not answering", it tells
  you the Jooki is in airplane mode and when the Wi-Fi returns. Tokens and music
  carry on the whole time. Protected by the parent code when one is set.
- For the tinkerers: message `OJ_AIRPLANE {minutes}` (1–1440, none = until the next
  start, `cancel: true` = back now), state `device.airplane`, flag
  `/data/mode/OJ_AIRPLANE`, v2 command `device.airplane`. Details in docs/24.
- **A Jooki that lost its Wi-Fi gets it back without the app.** Moved house, new box,
  new password: the Jooki only ever learnt its network from the old app, and stayed red
  and silent. Its Wi-Fi chip also listens over Bluetooth, and a new page,
  https://guillain-rdcde.github.io/OpenJooki/wifi.html, speaks to it from Chrome on an
  Android phone or a computer (Windows, Mac, Linux): it shows the networks the Jooki
  sees and the ones it remembers, you pick one, type the password, done in ten seconds.
  A network can be forgotten there too. Not from an iPhone or iPad: Apple keeps
  Bluetooth away from web pages, so that one step takes an Android phone or a computer,
  once. The Jooki's page now says so under *Settings → Wi-Fi*, with the name the Jooki
  shows in a Bluetooth list (`JOOKI2_…`). For a terminal: `tools/wifi/jooki_wifi.py`.
  Proven on a real Jooki, moved between two networks, wrong password reported.
- **Bluetooth speakers and headphones.** Jooki had built them into the Jooki 2
  (late 2022) and never put the button in the app. Settings → *Bluetooth speaker or
  headphones*: put the speaker in pairing mode, tap *Search*, then *Connect*. The
  sound moves to the speaker; if it switches off, the sound comes back to the Jooki,
  and when it is switched on again the Jooki reconnects by itself. *Stop using this
  speaker* forgets it. Connecting and forgetting are protected by the parent code.
  Proven on a real Jooki with a Sony SRS-X11. A connected speaker no longer keeps an
  idle Jooki awake (it used to), so the battery still switches off after 15 minutes.
  For the tinkerers: messages `OJ_BT_SCAN`, `OJ_BT_CONNECT {mac}`, `OJ_BT_FORGET {mac}`,
  state `bluetooth`; the ESP32's own protocol is in docs/26.

## SD card tools (28 September 2026) — a new card from scratch
- **A Jooki that no longer starts because its card died gets a new card**, with
  nothing to copy from anyone: the SD card tool (Windows, Mac, Linux) now starts with
  a choice, *a bigger card* or *a new card*. The second downloads OpenJooki's complete
  card image (seven partitions, the Jooki's own bootloader and factory system, the
  2.0.4 release on both system slots, empty data and music), checks it, writes it,
  reads it back and grows the music partition to the card. The image lives in a GitHub
  release of its own, `sdcard` (`openjooki-sdcard-2.0.4.img.gz` + `sdcard.json`),
  at a fixed address independent of the firmware releases, and rebuilt with every
  release so that a card always starts on the newest OpenJooki. Built by
  `tools/sdcard/make_card_image.py`. Plain-words guide: docs/25-new-sd-card.md and
  https://guillain-rdcde.github.io/OpenJooki/sdcard.html
- Fixed in the Windows tool: copying more than 2 GB stopped with a number-too-large
  error (a 32-bit arithmetic slip), so a real 8 GB card could not be copied. Found by
  the new-card bench; the bigger-card path benefits too.
- Release images: the build now removes the run-time leftovers of the Jooki an image is
  made from (`/tmp`, `/start`, stray files, authorized SSH keys) and zeroes the free
  blocks, and can be told strings that must not remain (`--forget`). **The 2.0.4 image
  was republished the same evening, scrubbed this way** (same program, new SHA-256 in
  `version.json`): the images from 1.3.0 to 2.0.4 carried the name and MAC address of
  the Jooki they were made from, and an authorized SSH key. A Jooki already on 2.0.4
  has nothing to do; its next update removes them.
- Not part of the firmware: nothing changes on a Jooki that works.

## OpenJooki 2.0.4 (28 September 2026) — any NFC tag, with its name and its photo
- **An amiibo, a sticker, any NFC tag can start a playlist.** Put it on the
  Jooki: it shows up on the *Tokens* screen as "NFC tag", and you pick its
  playlist there like for a character. From then on, putting it on starts that
  playlist. Two limits come from the Jooki's own NFC chip: taking the tag off
  does not pause (use the button), and the same tag twice in a row needs
  something else put on in between. Details in docs/23-nfc-tags.md.
- **The Tokens screen is now a wall of visuals, searched by name.** One tile per
  character or tag: its picture, its name, the playlist it starts. A search box
  above filters by name (a character's, a token's nickname, a tag's name or its
  playlist). Tap a tile to open its sheet: choose the playlist, name each token,
  forget one. Choosing a playlist another character already starts now asks
  first instead of taking it silently.
- **A photo for each tag.** In a tag's sheet, *Photo* takes a picture (or picks one
  from the gallery, or a file on a computer). The page then does the work itself,
  before anything is sent: *Remove the background* clears what touches the edges,
  a tap on any zone clears it too (a magic wand, with a tolerance slider), and
  rotation, zoom and drag frame the object in a circle. The Jooki only receives
  a 128-pixel picture of about 10 KB, kept on the memory card next to the album
  covers, so two hundred tags cost less than one song. *Remove the photo* drops it.
- **Name your tags.** A tag's tile is named by the end of its id until you type
  a name in its sheet ("Name this tag"); that name is then what the whole page
  shows for it, on the playlist cards too. With many tags, name them.

## OpenJooki 2.0.3 (28 September 2026) — a parent code, and switches you control
- **A parent code (optional, off by default).** In Settings, turn on a 4-digit
  code. Once it is on, each phone or computer asks for it once, then remembers it.
  Children and guests can still play music and change the volume, but can no
  longer delete playlists, change the Wi-Fi or start an update without the code.
  Forgot it? Hold the two arrows (◀ and ▶) together for ten seconds on the Jooki
  to clear it — whoever holds the Jooki is allowed.
- **Home automation (MQTT on the network), off by default.** For Home Assistant
  and the like: a switch in Settings opens the message bus to your network,
  protected by the Jooki's own password (shown right there: host, port, user,
  password). Off, the bus stays private to the Jooki.
- **A one-hour maintenance access (SSH), off by default.** For tinkerers: a
  switch opens SSH for an hour, then it closes on its own.
- **"Select all" in the library.** Above the list of tracks (all, or the unused
  ones the banner opens) a button selects every track shown, then flips to
  "Deselect all". Deleting the unused tracks no longer means ticking them one by
  one. It follows the search box: with a search typed, it selects only the matches.
- **Sort a playlist by file name, title, artist, album or duration.** Files
  numbered 1 to 6 land in a playlist in the order the uploads finish. The
  playlist page now has a *Sort* button: pick a criterion (a second tap reverses
  it), check the preview, then *Keep this order*. It replaces the old *Put back
  in order (1, 2, 3…)* button, which sorted by the title inside the file and so
  did nothing useful when the number was only in the file name.
- **Each playlist card shows its total length** next to the number of tracks
  (for example "6 tracks · 42 min").
- **The page speaks English first, and now Dutch.** English is the default; the
  page switches to French or Dutch on its own when the phone or computer is set
  to that language, and Settings has the three of them. A language chosen by hand
  is remembered.

## OpenJooki 2.0.2 (28 September 2026) — the page is the only way in
- **A booby-trapped website can no longer command your Jooki.** Until now any
  program on your Wi-Fi, including a web page open in a browser on a phone or
  computer at home, could reach the Jooki's message bus and, for example, delete
  playlists. The bus now listens only on the Jooki itself; over the network it is
  reached only through the page, and only with a password unique to your Jooki.
- **The password is created on the Jooki at first start and never leaves it.** The
  page reads it at the Jooki's own address; another website cannot read it and so
  cannot open the connection. Nothing changes for you: the page just works.
- No new setting, no account, no cloud. Your music, playlists and tokens are
  untouched. Checked on a family Jooki: the bus is refused from the network, the
  page connects with its password, a wrong password is refused.

## OpenJooki 2.0.1 (27 September 2026) — an update you can follow
- **While updating from the Jooki's page**: the steps in plain words under the
  spinner (looking for the new version, downloading with its percentage, checking,
  installing, checking the installation, restarting), instead of the installer's own
  output (the download meter was copied as is: unreadable and frightening on a phone).
- **No false "the update could not be done"**: a short loss of the connection while
  the Jooki is busy writing is no longer taken for a restart; the page waits for the
  installer to announce the restart, and recognises the new version when it comes
  back even if it missed that line. Seen on our Jooki: the page said the update had
  failed while it was still checking what it had written, then went on and succeeded.

## OpenJooki 2.0.0 (27 September 2026) — a brand new program inside
- **Our own program for the Jooki**, rewritten from scratch in readable Lua, in
  place of the original one: one event loop, pure handlers, all input and output
  behind adapters, a versioned contract (v2) with the page and the 1.x one kept,
  atomic data files shared with 1.x. Design: `docs/21-architecture-2.0.md`; what it
  replaces: `docs/22-core-inventory.md`; decisions: `docs/adr/`; the contract,
  generated from the code: `docs/api-v2.md`.
- **Faster start**: ready about a third sooner than 1.x (about 6.5 s instead of 8.9 s
  after the kernel on our Jooki). The player no longer waits 1 s at boot (the core
  repeats its orders to the Wi-Fi/NFC chip until it answers, so tokens never stay
  deaf), and the web server's folders are prepared in the background.
- **A name of your own** for the Jooki on the network (Settings → Name → Rename, e.g.
  `http://jooki.local`), kept across updates and restarts.
- **A home-screen icon** of our own and a web app manifest: full screen on iPhone, a
  sharp icon on Android.
- **The page on large screens** sits in a centred column.
- Everything 1.3.0 does is kept: the integration checks of the 1.x bench (backend,
  bedtime, network, page) pass unchanged on the new program, with its own unit specs,
  lint, size and memory budgets and an endurance run, all in CI. Spotify Connect and
  Deezer kept (optional `streaming` module, ADR-0009).
- Checked on a family Jooki since the morning of the release (six A/B installs, boot
  timeline measured in `dmesg` and in the program's own state, memory within budget),
  and a factory Jooki's data checked to survive the move to 2.0 and the way back to
  the factory program. Found and fixed on the device: a Jooki switched on while
  plugged in used to believe it was on battery (the charger is now read at boot).
- Release images no longer carry the name and MAC address of the Jooki they were
  made from.
- **A bigger SD card** (not part of the firmware): tools for Windows, Mac and Linux,
  https://guillain-rdcde.github.io/OpenJooki/sdcard.html

## Firmware 1.3.0 (26 September 2026) — bedtime
- **Audiobooks resume where the child fell asleep**: chapter and position are
  saved on the Jooki and survive it turning itself off; it starts again 15 s
  earlier (60 s after the sleep timer); the end of the book goes back to
  chapter 1; *Start again from the beginning* on the playlist page.
- **Sleep timer** (10–60 min or *end of chapter*) from the player, with a gentle
  fade of the volume before the pause.
- **Night mode** (default 20:00–07:00, Europe/Paris with summer time): automatic
  timer (20 min), volume limited (30 %) whatever the knob says, dimmed lights.
- **Put back in order (1, 2, 3…)** for playlists whose uploads arrived out of order.
- New messages `OJ_SLEEP`, `OJ_BEDTIME_SET`, `OJ_RESUME_RESET`; see `docs/19-bedtime.md`.
- **Network health** (`docs/20-network-health.md`): uploads retry on their own
  when the Wi-Fi drops (and a **Retry** button after 4 tries); Wi-Fi quality in
  Settings; **logs no longer sent to Muuselabs' Papertrail** and kept to one week
  on the Jooki (the old 39 MB log and 11 MB send queue are cleaned); the page
  answers at **`http://<its-name>.local/`** (e.g. `jooki2-a1b2c3.local`, shown
  in Settings), whatever address the router gives it.
- Bench: 57 unit + 24 bedtime + 13 network + 38 backend + 47 page checks;
  installed and checked on a real Jooki v2.

## Firmware 1.2.0 (2026-09-25) — update from the Jooki's own page
- **Settings** shows the installed OpenJooki version and checks GitHub for a
  newer release. When there is one, a banner appears on the home page and
  **Update now** installs it from the page itself (same safe A/B install as the
  phone installer, progress shown, the page reconnects by itself and confirms
  the new version). No need to go back to the installer page.
- Application: the state now carries the OpenJooki version (`device.openjooki`);
  two new messages `OJ_UPDATE_CHECK` / `OJ_UPDATE_START` (see `docs/18-web-ui.md`).
- Bench: 38 backend + 30 page checks.

## Firmware 1.1.0 (2026-09-25) — everything from the phone
- The **firmware now includes the new web page and the application fixes** of
  v0.4.0: a parent installs or updates from the phone installer page and gets
  the page, nothing else to do. Built from 1.0.0 by
  `scripts/add-webui-to-image.py` (edits the ext4 image with `debugfs`, checks
  it with `e2fsck`, reads every file back).
- Installer page: the end screen links to the Jooki's own page; realistic update
  time (a full image, up to 10 minutes); simpler "where is the IP" help.
- README: a simple guide for parents first, technical details below.

## v0.4.0 (2026-09-25) — a new web page, and the Jooki's own bugs fixed
New `jooki.py patch webui` (A/B, rollback armed, verified on a live device):
- **New local web page** at `http://<jooki-ip>/`: playlists, tokens, library,
  player and settings; **upload from a phone** (file picker) or a computer
  (drag and drop); reorder by touch or mouse; French/English; light/dark; no
  tracker, no external request, no dead-cloud link. Replaces the 2018 app
  (kept on the device, not served).
- **One rule for tokens**: every token of the same character starts the same
  playlist; a name is only a label. Old per-token links are migrated at boot.
- **Application fixes** in `player.lib` (patched in place, original kept):
  no more "No update required"; "Unused tracks" protected and always up to date;
  removing a song from it can no longer delete a file used elsewhere; failed
  uploads never delete existing files; a bad message can no longer crash the
  player; safer database writes; web radio validation; stale resume position,
  empty playlists, "previous" while paused, repeat/shuffle saving… See
  `docs/18-web-ui.md`.
- Tested on a bench running the real application (38 backend + 26 page checks)
  and on a real Jooki v2 (install + 12 non-destructive checks).

## v0.3.0 (2026-09-10) — phone-first install, proven end-to-end
The "factory Jooki → OpenJooki from a phone, no computer" path is now real and
**verified on a live device**: a factory Muuselabs Jooki v2, one tap on the
installer page, self-download → sha256 verify → A/B write → self-reboot →
OpenJooki 1.0.0 running, music and Wi-Fi intact.
- **Robust downloads**: every `curl` in the on-device scripts retries up to 5×
  (re-resolving DNS). Fixes a real failure — a **transient DNS drop** on the
  release CDN aborted the 39 MB firmware download; the retry recovers from it.
- **Simpler distribution**: the updater scripts (`o.sh`, `b.sh`,
  `openjooki-ota.sh`, `openjooki-selfupdate.sh`) are now served from **GitHub
  Pages**, so a fix ships with a plain `git push` — no release upload, no `gh`
  login. The firmware image + `version.json` stay as Release assets.
- **Installer page, rebuilt for non-technical users** (`docs/index.html`):
  much less text; a **confirmation** that sets expectations ("nothing shows on
  screen for ~10–15 min, that's normal, it restarts itself, don't unplug"); then
  a full-screen **spinner + countdown**; auto-closes the throwaway `ok` tab where
  the browser allows; accepts comma-or-dot IPs (iOS keypad) and remembers the IP.
- **Documented** the hard browser constraint (HTTPS page ↔ HTTP device =
  mixed-content: the command can only be fired via a visible tab, and status
  can't be read back), the SD partition map with real numbers, and the
  **reversible factory-revert** procedure — see `docs/16-phone-install.md` and
  `docs/04-architecture.md`.

## v0.2.1 (2026-09-09) — cross-platform (web) installer + "phone" groundwork
- **Local web installer** (`installer_web.py`) replacing the Tk GUI (macOS Tk does
  not render): page served locally, firmware **drag-and-drop**, progress bar,
  reliable rendering everywhere. **Mac / PC / Linux, one codebase.** Rendering
  verified (Safari) and upload (`/upload`) verified server-side.
- **`--lan`**: the server listens on the local network → you can **drive the
  install from your phone** (the computer does the work).
- **Optimized transfer** kept: a `.gz` image is sent compressed and decompressed on
  the device (~15× lighter on the network).
- **On-device self-install core**: `device/openjooki-selfupdate.sh` (validated with
  `ash -n`) — for the upcoming "phone, no PC" path via the Jooki's internal web
  server (web_ctrl/Mongoose, doc root `/jooki/app/www/public/`).
- Docs: `docs/14-cross-platform-installer.md` (status, feasibility, Bluetooth
  verdict: not suitable for firmware).

## v0.2.0 (2026-09-09) — "zero-effort" graphical installer
A real double-clickable Mac app to install a firmware **with no technical
knowledge**, with all the proven anti-brick protections.
- **OpenJooki Installer.app** (Tkinter, no dependencies): choose a firmware file,
  click, a progress bar does the rest. Clear result ("Done, your Jooki is running"
  / "automatic return to the previous version").
- **`installer.py` engine** — end-to-end safety:
  * writes only to the **spare** partition (never the active one or the boot);
  * **bit-perfect verification** (SHA-256 read back from the partition == source) —
    exact byte read via `dd` (this busybox has no `head -c`);
  * checks the image is a **bootable system** before activating;
  * **activation** via A/B with **armed U-Boot rollback** (auto return if it does
    not boot);
  * cleanly refuses (without activating anything) an image that is too big, too
    small, or not bootable.
- **Optimized transfer**: a compressed image (.gz) only sends the compressed bytes;
  **the Jooki decompresses** while writing (~15× lighter on the network).
- Verified 100% on the device: bit-perfect self-test (source hash = file =
  exact byte region); real end-to-end install of a real image (compressed transfer
  → bit-perfect check → activation p3→p2 → return to p3), Jooki intact.

## v0.1.2 (2026-09-09) — automatic rollback locked in
- `patch switch` (and therefore `cut-cloud`/`harden`) now **arms the U-Boot
  rollback** before each switch, exactly like a real Mender update: boot counter
  reset (`htdrv/bootcount` + env), trial boot (`upgrade_available=1`). If the new
  partition **does not boot**, U-Boot (`bootlimit=1`, `mender_altbootcmd`)
  **returns on its own** to the other partition — no computer, just a power-cycle.
- **Commit** automatically when the partition boots correctly
  (`upgrade_available=0` + `ht_reset_bootcount.sh`): no "pending" state lingers
  after a successful switch.
- Verified 100% on the device: armed cycle p3→p2→p3, `upgrade_available` flag going
  to 1 (armed) then 0 (committed) at each step, Jooki back to identical.

## v0.1.1 (2026-09-09) — security + robustness audit
Fixes from a professional audit of the existing firmware, applied and
**verified 100% on the device** (A/B partition, rollback preserved).
- New command `patch harden`: applies the fixes from the `patches/` folder via the
  A/B mechanism (clone → write to the copy → switch → per-file verification),
  **idempotent** ("already applied" when there is nothing to do) and **anti-brick**
  (automatic rollback if a file diverges, the spare partition is always unmounted
  even on failure).
- 5 fixes, delivered as **auditable** files in `patches/`:
  - `ble.sh` — neutralizes two backdoors (arbitrary code execution via the `u)`
    userset and `_)` custom cases); the legitimate functions are kept.
  - `run_rpc_cmd.sh` — refuses remote command execution (removes a TOCTOU
    "verify then execute" flaw).
  - `check_online.sh` — removes the infinite ping loop to the dead server.
  - `is_mounted.sh` — anchored mount test (`grep -qF " $1 "`), no more false
    positives.
  - `wait_for_file.sh` — adds a timeout (no more infinite wait).
- Fixed: `patches/ble.sh` contained an erroneous double backslash
  (`grep 'SSID\\|Not'`); realigned byte-for-byte with the verified version running
  on the device (`grep 'SSID\|Not'`).
- Reliability: file transfer via `cat`/heredoc (this busybox has no `base64`
  applet).

## v0.1.0 (2026-09-09) — first version
Safely taking back control of a Jooki v2 after the Muuselabs servers shut down.
- `openjooki` CLI tool (Python, no dependencies):
  - `discover`, `info`, `backup` (+`--quick`) — tested on a real Jooki.
  - `playlist list/new`, `music add` — re-adding music (upload + MQTT).
  - `patch status/clone/switch` — A/B firmware patch (clone + switch, proven).
  - `patch cut-cloud` — cuts the cloud heartbeat (phone-home + `## ML_OTA`
    backdoor), applied and verified on the device, with rollback.
- Full firmware analysis (docs/): architecture, MQTT bus, ESP32 protocol,
  content API, anti-brick A/B mechanism.
- Anti-brick promise: never touches bootloader/factory partition, backs up before
  writing, OS patches via A/B with rollback.
