# Test bench (off-device)

Runs the **real** Jooki application (the Lua program from your own Jooki's
`player.lib`) on a Linux machine, with a real mosquitto, an emulation of
`web_ctrl`, a fake audio engine and a headless Chromium, to test the fixes and
the web page end to end. It needs root (it creates `/jooki`, `/data/mode`,
`/tmp/web_ctrl_dirs` like on the device) — use a throwaway VM/container.

Requirements: `lua5.1`, `lua-socket`, `mosquitto`, `ffmpeg`/`ffprobe`,
Python 3 with `paho-mqtt` and `playwright` (Chromium).

```sh
# 1. get player.lib from your Jooki (ssh root@<ip> -p 2222 cat /jooki/lib/player.lib > player.lib)
python3 prepare.py player.lib          # -> player.lua + player.patched.lua (never commit them)
./make_media.sh                        # small test audio files
./up.sh                                # mosquitto (1883 + ws 8000), web_ctrl emulation (:8080), fake audio
python3 test_backend.py                # 38 checks of the application fixes
python3 e2e.py                         # 26 checks of the web page (Playwright)
```

`python3 test_backend.py player.lua` runs the same checks against the original
program: it fails right away (naming a token moves the character's playlist to
that single token), which documents the original behaviour.
