# NFC tags: Jooki tokens, and everything else

What the Jooki 2 does when something is put on it, measured on a real Jooki
(28 September 2026, OpenJooki 2.0.2, ESP32 firmware of 2 December 2022, API
0x0204) and read from that firmware (`/etc/esp32/factory_default_firmware.tgz`,
`jooki_v2.bin`).

## 1. Who reads the tag

The NFC reader is an ST **CR95HF**, driven by the **ESP32** (closed firmware,
`nfc_ctrl/hw_nfc.c` and `nfc_decrypt.c` in its build paths). Linux never sees
the tag's memory: the ESP32 sends up only what it has decided.

| Put on the Jooki | ESP32 log (`esp_tty`, syslog) | Bus | OpenJooki |
|---|---|---|---|
| a Jooki token | `TAG: new tag: <UID> 0x<code>` | `/j/nfc/input/tag` `"<UID>,<code>"` | its character's playlist |
| taking it off | `TAG: Tag removed` | `/j/nfc/input/tag_removed` | pause |
| any other tag (amiibo, sticker) | `NFC: EVT_BAD_TAG: tagId=<UID> - missing prefix` | nothing | see §3 |
| taking it off | nothing | nothing | nothing |

`<UID>` is the tag's 7-byte identifier in hex (14 characters). The ESP32 only
reports a tag when it **differs from the last one it saw**: a foreign tag put on
again, with nothing else in between, gives no second line. A Jooki token in
between resets it.

## 2. What a Jooki token contains

Credit: [SveLil/JookiTagCreator](https://github.com/SveLil/JookiTagCreator)
(MIT, 2023), which found the format.

A token holds one NDEF URL record, `https://s.jooki.rocks/s/?s=<16 characters>`
(this is the "prefix" the ESP32 looks for). The 16 characters are base64 of 12
bytes: `80 77 51` (fixed), the token type (1 = characters, 2 = coloured G2
tokens), the figure number, and the tag's own 7-byte UID, scrambled with a
fixed 13-byte key (`e[i] = d[i] ^ K[i]` for the first three bytes, then
`d[i] ^ K[i] ^ d[i % 3]`). The character code the bus carries is
`type << 8 | figure` (0x103 = Knight, 0x109 = Black whale, 0x210 = orange G2).

Because the UID is inside the scrambled content, copying a token's content to
another tag is refused (`EVT_CLONE_DETECT: tagId mismatch`). A blank NTAG213
sticker written with the content computed **for its own UID** should be read as
a genuine token (not verified yet). The Jooki itself cannot write tags: its
firmware says `Writing tags is not implemented`.

## 3. Other tags in OpenJooki (2.x)

syslog-ng (`tools/openjooki/system/syslog-ng.conf`) publishes the ESP32's
`EVT_BAD_TAG` line on the local bus, topic `/j/nfc/input/foreign`, with
`mosquitto_pub -l` (started again while the broker is not up). The core turns it
into `nfc.tag { uid, foreign = true }`:

- the tag becomes its own character, `tag.<UID>`, learned in `tokens.json`
  like any token, and shown on the page's *Tokens* screen as "NFC tag" + the
  end of its id (or the nickname given to it);
- a playlist is linked to it as to a character; putting the tag on starts it,
  and an unlinked tag plays the "empty" sound, so the family hears it was seen;
- it never claims `state.nfc` (the ESP32 will not report its removal, so the
  page would show it on the Jooki forever), and taking it off does not pause;
- it can carry a picture: the page edits the photo in the browser (flood-fill
  background removal, rotation, zoom, circle) and sends a 128 px PNG through
  the Jooki's `/upload` (the core's own web server since 2.1, `core/adapters/httpd.lua`;
  `web_ctrl` before), then `TOKEN_SET_IMAGE { tagId, uploadId }`. The core
  moves the file to `<data_dir>/artwork/tok_<UID>.png` (served at `/artwork/`)
  and stores its address in `tokens.json` (`image`, with the file size as a
  cache key). `TOKEN_EDIT { image: false }` removes both.

Limits, all on the ESP32's side: no pause on removal; the same tag twice in a
row needs another tag in between (or the play button); the tag must sit close
to the reader (an amiibo's base is wider than the Jooki's hollow and reads only
at the right angle).

## 4. Flat tokens and the Thank-you token: one code, many tokens (2.2)

The round flat tokens (sold with a cat, an elephant, a rocket… printed on them)
all carry the same character code, **512** (`Jooki.Flat`), and the Thank-you
token carries **260** (`Jooki.ThankYou`). By the character rule they were one
single character: every flat token started the same playlist. Since OpenJooki
2.2 each of them is a character of its own, named after its UID:
`flat.<UID>` and `thanks.<UID>` (`core/services/tokens.lua`, `tokens.own_star`;
the prefixes live in `library.PER_TOKEN`).

- They are genuine Jooki tokens: they claim `state.nfc`, the page shows them
  on the Jooki, and taking one off pauses — unlike a foreign tag.
- A flat token without a playlist of its own plays the playlist linked to the
  shared `Jooki.Flat` character, as before 2.2 (the same for `Jooki.ThankYou`).
  So nothing changes for a family until it gives a token its own playlist.
- Tokens learned before 2.2 are renamed at boot (`library.ops.normalise`:
  `starId "Jooki.Flat"` -> `"flat.<UID>"`); their names and pictures stay.
- On the page they behave like a foreign tag: one tile per token, a name, a
  picture (§5), a playlist.

## 5. A picture for a token of its own: the library (2.2)

A token that is a character of its own (`tag.`, `flat.`, `thanks.`) can carry a
picture, stored in `tokens.json` as `image`. Two forms only, checked by the core
(`library.ops.valid_image`; anything else is refused with `invalid_argument`):

- `lib:<id>`: one of the page's ready-made pictures, `webui/tokimg/<id>.webp`
  (served at `/tokimg/`). 659 pictures of Fluent Emoji 3D (Microsoft, MIT
  licence, `tokimg/LICENSE.txt`), 128 px WebP, 2.5 MB in all, in 16 families;
  `tokimg/index.json` gives their family and their names and search words in
  English, French and Dutch (Unicode CLDR, shortened by hand, plus children's
  words such as "minou" or "doudou"). They ship with the system image, so they
  work without Internet. The core's web server lets the phone keep them
  (`Cache-Control: max-age`, `/tokimg/*.webp` only). `webui/make_tokimg.py`
  rebuilds the folder.
- `/artwork/tok_<UID>.png?v=<size>`: a photo edited on the page (§3).

`TOKEN_EDIT { tagId, image: "lib:<id>", name? }` sets a library picture (the
page also gives the picture's name to a token that has none); a photo replaced
that way, or removed with `image: false`, has its file deleted.

Since 2.4 the cover of a book read in Jookistory can be that photo: the studio hands it over
with the story (`cover` in its `oj-story` message, `cover.jpg` in its zip), and the page sends
a 128 px circle of its middle through the same `/upload` + `TOKEN_SET_IMAGE` path
(`coverToToken`, `webui/src/08b-story.js`), only for a token of its own.

### A token put on the Jooki while a sheet waits (2.4)

The *Which token starts this story?* sheet (and *Choose the character*) watches what the Jooki
reports: `state.nfc.starId` for a genuine token (a character, a flat token), and the `seen`
counts in `db.tokens` for a foreign tag, which never claims `state.nfc` (§3). The first
character that changes is picked (`watchToken`, `08b-story.js`). The labels page
(`#/tokens/labels`) lists the tokens of their own with their picture and playlist, printed as
25, 30 or 40 mm circles (`@media print` in `app.css`). Whether the reader sees a sticker
through a book's cover is a question of thickness: the tag must sit close (§3); the guide says
to try, and to put the sticker inside the cover when it fails.

## 6. Do not

- `esp32_cmd set_nfc_mode`: setting 0 turned the reader off, and setting 1 again
  answered "ok" without turning it back on. Only a restart of the Jooki did.
- Polling `esp32_cmd get_tag` in a loop while the Jooki is in use: it shares the
  channel with `esp32_ctrl`, and every call writes a log line. `get_tag` only
  ever reports genuine tokens.
- Reflashing the ESP32: the one real way to brick the Jooki.
