# The page's script, one file per subject

`app.js`, the file the Jooki serves, is these files put end to end by `../build.py`, in name
order, inside one closure. Nothing is transformed: no bundler, no minifier, no module system.
Edit here, then:

```sh
python3 tools/openjooki/webui/build.py          # writes ../app.js
python3 tools/openjooki/webui/build.py --check  # what CI runs: app.js must be what src/ gives
```

Each file is a run of statements of the same function, so they all share their variables, as
when it was one file of 3 000 lines. The order matters only for what runs while the file loads
(a `var x = …` used by a later top-level line); functions may call each other across files.

| File | What is in it |
|---|---|
| `00-config.js` | `CFG`, `VERSION` (written by `scripts/bump-version.sh`) |
| `01a`…`01e-i18n` | the texts: one table per language (same keys in each), then `t()`, language and theme |
| `02-characters.js` | the characters and tokens' names and pictures |
| `03-helpers.js` | `h()` the DOM builder, icons, formats, the collator |
| `04-state.js` | the Jooki's state as the page keeps it, and its per-state index |
| `05-connection.js` | MQTT over WebSocket, the parent code, messages in and out |
| `06-toasts-modals.js` | toasts, modals, the form helpers |
| `07-discs.js`, `08-uploads.js` | FLAC/WAV to MP3 in the browser, albums; the upload queue |
| `08b-story.js` | a story read in the studio (`docs/studio.html`, another tab) comes back as an audiobook playlist; a token put on the Jooki while a sheet waits; the book's cover as the token's picture |
| `08c-story-file.js` | a story received as one file (the studio's zip) opened as a playlist |
| `09-token-visuals.js`, `10-routing.js` | a token's picture; the hash routes and the UI state |
| `11`…`14-view-*.js`, `12-drag-reorder.js` | the screens: playlists, a playlist, the library, the tokens |
| `15-picture-library.js`, `16-token-photo.js` | the pictures for tokens; the photo editor |
| `17-update.js` | OpenJooki updates from the page |
| `18-settings.js`, `19-bedtime.js`, `20-sort.js` | Settings and its topic pages; night mode and sleep timer; sorting a playlist |
| `21-player.js`, `22-render.js`, `23-boot.js` | the player bar and sheet; `render()`; start-up |
