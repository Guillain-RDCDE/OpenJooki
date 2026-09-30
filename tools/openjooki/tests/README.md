# Test bench (off-device)

A Jooki without the Jooki: the **real OpenJooki core** (built from `core/`) runs on a Linux
machine with a real mosquitto, fake hardware around it and a headless Chromium, to test the core
and the web page end to end. It needs root (it creates `/jooki`, `/data/mode`,
`/tmp/web_ctrl_dirs` like on the device): use a throwaway VM, container or WSL distribution.
The CI runs exactly this (`.github/workflows/ci.yml`, job *oracle*).

Requirements: `lua5.1`, `lua-socket`, `mosquitto`, `ffmpeg`/`ffprobe`,
Python 3 with `paho-mqtt` and `playwright` (Chromium).

| On the device | On the bench |
|---|---|
| the core (`/jooki/lib/core.lua`), serving the page on port 80 | the same core (`build/`), page on **8090** (`start_player.sh core`) |
| mosquitto, 1883 local + WebSocket 8000 with a password | `up.sh`: the same, fixed password `jooki`/`benchsecret` |
| audio, ESP32, power controllers (closed binaries) | `fake_audio.py`; the tests play the others' part on the bus (`jk.py`: tokens, buttons…) |
| the system scripts it calls (`/jooki/app/services/*.sh`) | stubs written by `setup.sh`, each call logged in `/tmp/bench_services.log` |
| the clock (Internet time, none without it) | the machine's clock, always set: the "no time" case is in the specs (`core/spec`) |

`webctrl_emu.py` (port 8080) emulates the original `web_ctrl`; only the 1.x program uses it
(`PLAYER_LUA` unset). The tests find the page through `jk.PAGE` (`OJ_PAGE_URL` to override).

```sh
(cd ../../.. && python3 tools/build/bundle.py)   # the core, into build/ at the repository root
export PLAYER_LUA=core CORE_BUILD=$(cd ../../.. && pwd)/build
./make_media.sh && ./up.sh                    # test audio, broker, fake audio
python3 test_backend.py && python3 test_bedtime.py && python3 test_net.py
python3 test_security_backend.py && python3 e2e.py && python3 test_security.py
python3 test_spotify.py && python3 test_robustness.py && python3 test_loader.py
python3 test_httpd.py && python3 test_clock.py && python3 test_wifi_page.py
python3 ../../../core/spec/integration/endurance.py 3
```

The unit specs run without any of this: `lua5.1 core/spec/run.lua` from the repository root.
