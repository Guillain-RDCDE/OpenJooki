# Third-party code and media in this repository

What OpenJooki takes from others, where it comes from, which version, and under which licence
(ADR-0006: minimal, vendored, pinned; an update is an explicit commit that also updates this file).
Each version below was checked against the file itself and its upstream, not taken from memory.

| What | Where in this repository | Upstream | Version | Licence |
|---|---|---|---|---|
| json.lua (rxi), the core's JSON | `core/vendor/json.lua`, licence `core/vendor/json.LICENSE` | https://github.com/rxi/json.lua | commit `11077824d7cfcd28a4b2f152518036b295e7e4ce` (5 April 2020), see below | MIT, Copyright (c) 2020 rxi |
| lamejs, the MP3 encoder of the page and of Jookistory | `tools/openjooki/webui/lame.min.js` (copied to `docs/lame.min.js` by `tools/openjooki/webui/build.py`), licence `lame.LICENSE.txt` next to it | https://github.com/zhuker/lamejs, npm package `lamejs` | 1.2.1, unmodified | LGPL-3.0 |
| Fluent Emoji 3D (Microsoft), the ready-made token pictures | `tools/openjooki/webui/tokimg/*.webp` (659 pictures, 128 px WebP), licence `tokimg/LICENSE.txt`; 24 of them copied unchanged to `docs/img/studio/*.webp` for Jookistory | https://github.com/microsoft/fluentui-emoji | branch `main`, most likely commit `1ffb34c752ecf5d402f04cfb4b392c77f57c54bc`, see below | MIT, Copyright (c) Microsoft Corporation |
| Unicode CLDR annotations, the names and search words of the token pictures | `tools/openjooki/webui/tokimg/index.json` (names shortened by hand) | https://github.com/unicode-org/cldr-json, npm packages `cldr-annotations-full` and `cldr-annotations-derived-full` | 46 (the major version `make_tokimg.py` asks for; the exact 46.x release was not recorded: unknown) | Unicode License v3 |

## How each version was checked

- **json.lua**: the header still says `_version = "0.1.2"`, but the file is not the `v0.1.2` tag
  (19 June 2019): it has the copyright year 2020 and the rewritten `parse_string` of 5 April 2020.
  Line endings aside, it is byte for byte the upstream `json.lua` at commit `11077824` ("Updated
  copyright year: 2019 => 2020"), which is also the last upstream commit to touch that file.
  So: 0.1.2 plus the two upstream commits after it, with no change of ours.
- **lamejs**: `sha256(lame.min.js)` =
  `15d285e2587b3bdbfd18a68de6ce07cc074f7480a82c3815da2dc1c348ec6df4`, the same as `lame.min.js`
  inside https://registry.npmjs.org/lamejs/-/lamejs-1.2.1.tgz (whose `package.json` says version
  1.2.1, licence LGPL-3.0). The tarball itself has sha256
  `d8d099ef788808c15bc9b4a407dd23ae935feb1152e6bb0efdcd24e3e91c2a2d`: the hash written in
  `lame.LICENSE.txt` is the one of `lame.min.js`, not of the tarball.
- **Fluent Emoji**: `tools/openjooki/webui/make_tokimg.py` downloads from the `main` branch and
  does not write down the commit. The pictures were added on 1 October 2026 (commit `618fa66`);
  upstream `main` had not moved between 24 August 2026 (`1ffb34c`) and then, so that is the
  commit they come from, unless they were downloaded before 24 August (the previous upstream
  commit is `62ecdc0`, 30 January 2025). The pictures were resized and converted to WebP.

## What is ours (not third-party)

The MQTT client of the core (`core/adapters/mqtt_codec.lua`, `core/adapters/bus.lua`) and of the
page (`tools/openjooki/webui/mqtt.js`), the MP3 worker (`mp3-worker.js`), the sounds behind the
voice in Jookistory (made by code in `docs/studio.html`), the QR code picture
`docs/img/studio/qr.svg` (a generated picture, no code), and the Mac and Windows SD-card helpers.
No web fonts and no script from another website are used: the pages load nothing from outside.
