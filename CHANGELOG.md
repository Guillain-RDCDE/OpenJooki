# OpenJooki — Changelog

## Next release
- **The update screen no longer looks stuck for ever.** On a phone that went to sleep during an
  update (an iPhone above all), the page kept believing it was connected, never tried again and
  stayed on "Installing" long after the Jooki was back. The page now notices a dead connection
  when it comes back in front, and every ten seconds during an update, and connects again. If
  nothing has moved for three minutes it says why that can happen and offers *Reload the page*,
  which stops nothing; the phone that started the update shows it again after a reload.

## OpenJooki 2.2.6 (3 October 2026) — tidied inside, and a handful of fixes
- **The parent code now also guards the v2 commands.** Over the newer command channel the page
  does not use yet (`/j/web/v2/cmd`), deleting a playlist, starting an update or changing a
  setting went through without the parent code. The same gate now answers both channels
  (`"code"` in the v2 envelope; error `forbidden` / `PARENT_CODE_REQUIRED`).
- **Shuffle really shuffles.** The random order was seeded with a value never set, so a playlist
  played in the same "random" order after every start, and two playlists of the same length in
  the same one. The seed now comes from the clock at start-up.
- **Dutch names for the characters.** The Dragon, the Fox and the others had no Dutch name and
  showed up in French on a page in Dutch.
- **The updater's addresses come from the configuration** (`update_manifest_url`,
  `update_script_url`, restricted to our GitHub or the bench's own server). The bench no longer
  reaches GitHub, and the CI no longer runs the real `o.sh` as root.
- **The firmware image no longer carries traces of the Jooki it was built from.** The name and
  Wi-Fi address of the maintainer's own Jooki survived in unused blocks of the images of 2.0 to
  2.2.5 (the new-card image was checked for them, the firmware image was not): the clean-up
  skipped those blocks whenever it had just repaired the filesystem. The build now cleans until
  nothing is left and refuses to produce an image where they can be found.
- Fixes in the tools: `openjooki-selfupdate.sh --force-model --dry` really is a dry run (the
  options were read by position); `installer.py` makes the same two checks as the other install
  paths before writing (the running system is on the active partition, p2 and p3 are twins);
  the "original card" tool also removes `/jooki/lib/core.lua`; a lost log line on a duplicate
  upload whose playlist add fails.
- **The 1.x patched program and its tooling are retired (ADR-0012).** `lua_patches.py`, the
  `patches/` folder, the 1.x bench and the `playlist` / `music add` / `patch cut-cloud` /
  `patch harden` commands of `jooki.py` are gone (the page does all of that; the two content
  commands had stopped working when 2.1 closed the broker). `patch webui` and
  `add-webui-to-image.py` require `--core`. The `player.lib` container codec lives in
  `tools/openjooki/playerlib.py`, shared by the build, the device tool, the release script and
  the loader test. A Jooki still on 1.x updates like any other (its page, the phone path, a card).
- **An audiobook's "will resume at chapter…" line shows as soon as the page opens.** The first
  state the page receives lacked the resume points; they only came with the next bedtime update.
- **A change made right after another one reached the page late.** The Jooki sends its state at
  most four times a second; when a second change fell inside that window it waited for the next
  unrelated event instead of the end of the window. Mostly hidden by a timer that ticked every
  half-second; now the state goes out when the window ends, whatever else happens.
- In English and Dutch the page no longer puts a French space before a colon ("Playlist : X").
- **Dead code removed**, nothing visible: in the core (unused kernel helpers, four shell actions
  nobody called including `factory_reset`, bus subscriptions nothing handled, three config keys
  never read, handler registrations no event reached), in the page (48 translations never shown,
  two icons, unused CSS rules, the service worker that only unregistered itself: the page already
  does that), and in the tools (an abandoned Tk installer, duplicate copies of the device scripts,
  a stale backup script, the stray `version.json` at the repository root).

## OpenJooki 2.2.5 (3 October 2026) — Settings pages stay still
- **The pages inside Settings no longer blink.** Night mode, Update, Bluetooth, Wi-Fi and the
  other pages opened from Settings flickered, again and again, since 2.2.0: their small fade-in
  played each time the Jooki sent news, which is often. It now plays once, when you open the page.

## OpenJooki 2.2.4 (2 October 2026) — discs keep going behind another tab
- **A disc keeps converting while you do something else.** Left behind another browser tab, a disc
  seemed to stop: Chrome slows the timers of a hidden tab, after five minutes to one a minute, and
  the page waited up to a minute between two tracks. The steps now follow one another without a
  timer. If your browser's energy saver still freezes the tab, add `jooki.local` to its sites that
  always stay active (in Chrome: *Settings > Performance*).

## OpenJooki 2.2.3 (2 October 2026) — your FLAC discs, three times lighter
- **Your discs in FLAC, three times lighter.** FLAC and WAV files are now turned into MP3 on your
  computer or phone, in the page, before they are sent: an album takes about 100 MB instead of
  300, and goes over three times faster. Title, artist, album, track number and the cover are kept
  (the cover made small, 300 px). Quality: 256 kbps, or 192 / 320 in *Settings > MP3 quality*.
  Your FLAC files stay at home, untouched.
- **Drop a disc, get a playlist.** On a computer, *Add albums* (or drop the folders on the
  playlists page): each folder becomes a playlist named after its album, its tracks in the disc's
  order, ready to be given a token. The cover.jpg, .cue and .log files are left out.
- For the tinkerers: decoding by the browser (resampled to 44.1 kHz), encoding by lamejs 1.2.1
  (LGPL-3.0, `webui/lame.min.js`, `lame.LICENSE.txt`) in a Web Worker (`mp3-worker.js`), ID3v2.3
  tags written by the page. Nothing changes on the Jooki itself.

## OpenJooki 2.2.2 (2 October 2026) — http://jooki.local/ works every time
- **`http://jooki.local/` works every time.** Opening the page by its name often failed while the
  address (192.168.1.x) worked. The Jooki's Wi-Fi chip misses most of the questions "who is
  jooki.local?" that phones send to the whole network: one in five got through on our Jooki. Now
  the Jooki says its name by itself, every 30 seconds, and the phone remembers it. On a phone, type
  `http://` in front of `jooki.local`.
- For the tinkerers: unsolicited mDNS announcements (A, cache-flush, TTL 120) at once, 1 s and 3 s
  after getting an address, then every 30 s; questions written with name compression (A + AAAA in
  one packet) are now read, and echoed in full in unicast answers. Details in docs/20.

## OpenJooki 2.2.1 (1 October 2026) — a Christmas tree, dark or light
- **Dark or light, your choice.** The page already turned dark when the phone was in dark mode.
  Now *Settings > Appearance* lets you choose: *Automatic* (like the phone, as before), *Light* or
  *Dark*. The choice is kept on that phone only: each parent can have their own.
- **A Christmas tree, just for fun.** In *Settings*, *Christmas tree* makes the ring and the two
  side lights run through all their colours for 5 seconds, then they go back to normal. It changes
  nothing else. At night, with night mode on, it stays dimmed like every other light.
- For the tinkerers: message `OJ_PARTY {}`, v2 command `device.party` (not behind the parent
  code). The heart is left to the light controller.

## OpenJooki 2.2.0 (1 October 2026) — every flat token its own, a picture library, new Settings
- **Each flat token can start its own story.** The round flat tokens (a cat, an elephant, a
  rocket printed on them) all carry the same code, so the Jooki saw them as one single token and
  they all started the same playlist. Now each one is a token of its own: give the cat one story
  and the elephant another. Taking one off pauses, like any Jooki token. Until a flat token has a
  playlist of its own, it keeps playing the one all the flat tokens played before. The Thank-you
  token works the same way.
- **659 ready-made pictures for your tokens.** On the *Tokens* screen, a flat token, an amiibo or
  an NFC sticker gets a picture in two taps: *Choose a picture*, then pick one — animals, tales,
  vehicles, food, music, space… with a search that knows children's words. A token without a name
  takes the picture's name. *My photo* is still there for your own picture. The pictures are on
  the Jooki: no Internet needed.
- **A new Settings page.** Shorter: a card with your Jooki's name, battery, storage and version,
  then one line per setting, with its value at a glance. The details (night mode, Bluetooth,
  airplane mode, Wi-Fi, update, language, parent code) open on their own page. Small texts no
  longer touch the edges of the cards.
- For the tinkerers: per-token characters `flat.<UID>` / `thanks.<UID>` (codes 512 and 260),
  migrated at boot, falling back to the shared `Jooki.Flat` playlist
  ([docs/23](docs/23-nfc-tags.md) §4). A token's `image` is now checked by the core: `lib:<id>` or
  the page's own `/artwork/tok_<UID>.png?v=<n>`, nothing else. The pictures are Fluent Emoji 3D
  (Microsoft, MIT), 128 px WebP in `webui/tokimg/` (2.5 MB), served with a long cache by the core's
  web server, which now knows WebP. `jooki.py patch webui` sends that folder as one tar;
  `add-webui-to-image.py` writes it in one debugfs run.

## OpenJooki 2.1.5 (1 October 2026) — Spotify's album covers
- **Spotify's album covers on the page.** While Spotify plays on the Jooki, the page showed a grey
  disc instead of the cover: the page's own safety rules blocked pictures coming from Spotify.
  Covers now show, in the bar at the bottom and in the big player. Tested on a family Jooki with
  Spotify on an iPhone.
- For the tinkerers: the page's CSP now allows `img-src https://*.scdn.co https://*.spotifycdn.com`
  (the daemon sends `https://i.scdn.co/image/…`; a `spotify:image:<id>` would be turned into that
  address too). The test bench now tests the page as the Jooki serves it since 2.1.0 (the
  core's own web server, port 8090 on the bench) instead of an emulation of the old `web_ctrl`.
  That showed the core's web server could not restart on LuaSocket 3 (reuseaddr set before the
  socket existed): fixed with `tcp4()`, and if the port is ever busy at start the server now tries
  again by itself (5 s, then up to every 60 s) instead of staying down. The Jooki itself
  (LuaSocket 2.0.2) was not affected.

## OpenJooki 2.1.4 (30 September 2026) — night mode away from home
- **Night mode works away from the Internet.** The Jooki has no clock of its own: it takes the
  time from the Internet, and forgets it when switched off. On holiday, without the Internet,
  it did not know whether it was night, so night mode (low volume, dim lights, sleep timer) did
  nothing. Now, when you open the Jooki's page, it takes your phone's time. A Jooki that
  already knows the time is left alone. Tested on a family Jooki.
- **A new page: [Away from home](guide/travel.md)** — what works without Wi-Fi, what to do
  before leaving, and how to use the page on holiday.
- For the tinkerers: the page sends `OJ_TIME {utc}` at every connection (v2 `device.clock`, no
  parent code); the core runs `date -u -s @utc` only while its clock is before 2024. `SET_WIFI` /
  `device.set_wifi` are now refused with `WIFI_OVER_BLUETOOTH`: they ran the Jooki 1's
  `wifi_add_network.sh`, which never reaches a Jooki 2's Wi-Fi chip and first switched the voice
  to English. The page never used them. A network is given over
  Bluetooth ([wifi.html](https://guillain-rdcde.github.io/OpenJooki/wifi.html)).

## OpenJooki 2.1.3 (30 September 2026) — the real fix for no sound from the speaker
- **Fully fixes the Jooki going silent** (2.1.2 only half-fixed it). The Jooki v2 has no wired
  headphone jack, but it still reported one as "plugged" when nothing was there — so it sent the
  sound to a jack that does not exist and switched the speaker off. A token or Spotify then looked
  like it was playing, in silence, whatever you did with the volume, until you plugged in a cable.
  The Jooki no longer listens to that false headphone detection: the speaker stays on. (Bluetooth
  speakers and headphones are unaffected.) Tested on a family Jooki, on battery.

## OpenJooki 2.1.2 (30 September 2026) — sound from the speaker on battery
- **Fixes no sound from the speaker after a start-up on battery.** The Jooki turned its
  amplifier on only when you plugged or unplugged headphones, not at start-up — so if it
  started with no headphones, a token or Spotify looked like it was playing but nothing came
  out of the speaker, until you plugged in a cable (which happened to switch the amplifier on).
  The amplifier is now switched on at start-up, like the original firmware. Tested on a family
  Jooki on battery.

## OpenJooki 2.1.1 (30 September 2026) — the side lights show it's waking up
- **While the Jooki looks for its Wi-Fi after you switch it on, the two side dots now glow
  back and forth, left then right, instead of sitting still orange.** A steady pair looked
  like it had frozen; the little animation says plainly "I'm waking up, hold on". It takes
  the chip about a minute to join the network at start-up (that part is inside the closed
  Wi-Fi chip, we can't speed it up) — meanwhile your tokens and music already work. The
  glow stops on its own the moment the Wi-Fi is found, or as soon as you play something.

## OpenJooki 2.1.0 (30 September 2026) — the Jooki serves its own page; a hidden door is closed
- **A hidden way to control the Jooki over Wi-Fi is closed.** Until now a small built-in
  program (from the original maker) answered, to anyone on your Wi-Fi and with no password,
  a request that ran commands on the Jooki as the top user, and requests that could reboot it
  or wipe it. That program is no longer started. Nothing you do changes; this only closes a
  door that should never have been open.
- **The Jooki now serves its own page.** OpenJooki shows the page and receives the songs and
  pictures you send, itself. It answers only those two things — the page and your uploads —
  and refuses a request coming from another website.
- **Room to grow again.** The program had reached the size the Jooki could load. It is now
  kept in its own file, so it is no longer boxed in, and new features have room. Nothing
  changes for you; the Jooki starts and runs just as fast (measured on a family Jooki).
- For the tinkerers: `web_ctrl` is not launched any more (`/ll` and `/cmd/*` are gone); the
  core serves the page and `POST /upload` over a small non-blocking server (`adapters.httpd`,
  port 80). `player.lib` is a <1 KiB loader that reads the real core from `/jooki/lib/core.lua`
  (ADR-0011, no more 200 KiB ceiling on the core). Maintenance SSH is opened from the page over
  the WebSocket. See ADR-0007 (now fully built) and ADR-0011.

## OpenJooki 2.0.9 (29 September 2026) — a steadier Wi-Fi
- **The Jooki stays on the Wi-Fi next to it.** Until now, every time it was switched on,
  the Jooki's Wi-Fi chip crashed once (an old Muuselabs setting did it), and it could come
  back on another Wi-Fi of the house, even a far one. That is gone. Tried ten times on a
  family Jooki: always on the right Wi-Fi.
- **About a minute and a half to get the Wi-Fi after switching it on**: that's normal.
  Tokens and music work in the meantime.
- **Keep only the Wi-Fi next to the Jooki.** The Jooki does not pick the strongest Wi-Fi:
  after a short cut it can move to another one it knows and stay there. On the
  [Wi-Fi page](https://guillain-rdcde.github.io/OpenJooki/wifi.html), forget the others.
- **The Wi-Fi page no longer disconnects a Jooki that works.** Finding the Jooki, seeing
  the networks it remembers and forgetting one leave its Wi-Fi alone. Only *Look for
  Wi-Fi networks* takes it off its Wi-Fi for a moment, and the page says so.
- **It gets its Wi-Fi back by itself, in more cases.** It now also notices when it
  believes it is connected but is not, and restarts quietly, as below.
- **Tokens and buttons keep working** even when a part of the Jooki has to restart.
- For the tinkerers: `esp32_cmd add_ap` crashes the chip (the original start script ran
  it at every boot); a Bluetooth set-up session takes the chip off its Wi-Fi; the chip
  keeps the last network it reconnected to by itself. Details in docs/20.

## OpenJooki 2.0.8 (29 September 2026) — a safer start
- **The Jooki gets its Wi-Fi back by itself.** Sometimes the Jooki stayed off its Wi-Fi
  until someone switched it off and on. Now, after ten minutes without Wi-Fi, on the
  charger and with nothing playing, it restarts by itself, without its chime. Twice at
  most in a row: if the Wi-Fi is really gone (moved house, new box), the
  [Wi-Fi page](https://guillain-rdcde.github.io/OpenJooki/wifi.html) is the way. Never
  in airplane mode, never during an update.
- **No more Muuselabs factory Wi-Fi.** The Jooki no longer tries a Wi-Fi that no home
  has.
- **Nothing goes deaf.** If the part of the Jooki that carries the tokens, the buttons
  and the page stops, the Jooki starts it again by itself.
- **Safer SD card.** A file put on the card from a computer can no longer change the
  Jooki's security settings.
- For the tinkerers: the maintenance access (Settings, one hour) takes an SSH public
  key, kept on the Jooki across updates, only while the access is open and behind the
  parent code when one is set. The broker (mosquitto) is started again after 20 s
  without it, with the hardware controllers. Details in docs/20.

## OpenJooki 2.0.7 (29 September 2026) — a character for your Spotify playlist
- **Spotify connects again after a restart.** After some restarts, the phone saw the
  Jooki in its list of devices but could not connect to it. Fixed, and checked on a
  family Jooki.
- **Put your Spotify music on a character.** While Spotify plays on the Jooki, open
  the player at the bottom of the page and tap *Put on a character*: pick a name and
  a character. Then the character plays that Spotify playlist, even without the
  phone; taking it off pauses it. The Muuselabs app had this; OpenJooki's page did
  not. The Spotify account must stay connected to the Jooki.
- **Who sings it.** Under a Spotify song the page now shows the artist and the album
  ("Albin de la Simone / Happy End"), where it showed only the album.
- **Settings on a big screen.** On a wide screen the page background stopped halfway
  down long pages such as Settings. It now goes to the bottom.
- For the tinkerers: the core now tells spotify_ctrl the network state at every Wi-Fi
  report (it answered only once, at start, sometimes before the Wi-Fi was up).

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
- **The page is never out of date.** After an update, a phone could keep showing the
  old page (Settings said "OpenJooki 2.0.5, page 2.0.4", and the new settings were
  missing). Now the page sees it and loads itself again, once, on its own.
- For the tinkerers: checked on the bench with a stand-in for the Spotify program, in
  both orders its messages can come in (`tools/openjooki/tests/test_spotify.py`, in CI).

## SD card tools (29 September 2026) — back to the original Jooki
- **The original Jooki, on a card.** The SD card tool (Windows, Mac, Linux) has a third
  choice, *The original Jooki: back to the program it was sold with*: a complete card with
  Muuselabs' own program of December 2022, without OpenJooki and without anyone's music. For
  whoever wants a Jooki back exactly as it was sold. The Jooki's own card stays the way back.
  Honest note shown in the tool: the official app and Jooki's servers are gone, so the
  original program can no longer be set up from a phone.
- For the tinkerers: it is rebuilt from an OpenJooki image, which keeps every file it replaced
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
