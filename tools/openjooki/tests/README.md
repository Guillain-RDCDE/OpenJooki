# Test bench (off-device)

A Jooki without the Jooki: the **real OpenJooki core** (built from `core/`) runs on a Linux
machine with a real mosquitto, fake hardware around it and a headless Chromium, to test the core
and the web page end to end. It needs root (it creates `/jooki`, `/data/mode`,
`/tmp/web_ctrl_dirs` like on the device): use a throwaway VM, container or WSL distribution.
The CI runs exactly this (`.github/workflows/ci.yml`, job *oracle*).

Requirements: `lua5.1`, `lua-socket`, `lua-filesystem`, `mosquitto`, `ffmpeg`/`ffprobe`,
Python 3 with `paho-mqtt` and `playwright` (Chromium), at the versions pinned in
`requirements.txt` (what CI installs, `.github/actions/bench`).

| On the device | On the bench |
|---|---|
| the core (`/jooki/lib/core.lua`), serving the page on port 80 | the same core (`build/`), page on **8090** (`start_player.sh core`) |
| mosquitto, 1883 local + WebSocket 8000 with a password | `up.sh`: the same, fixed password `jooki`/`benchsecret` |
| audio, ESP32, power controllers (closed binaries) | `fake_audio.py`; the tests play the others' part on the bus (`jk.py`: tokens, buttons…) |
| the system scripts it calls (`/jooki/app/services/*.sh`) | stubs written by `setup.sh`, each call logged in `/tmp/bench_services.log` |
| the clock (Internet time, none without it) | the machine's clock, always set: the "no time" case is in the specs (`core/spec`) |

The tests find the page through `jk.PAGE` (`OJ_PAGE_URL` to override). Only the core runs here:
the 1.x patched program and its `web_ctrl` emulator left with ADR-0012.

```sh
(cd ../../.. && python3 tools/build/bundle.py)   # the core, into build/ at the repository root
export PLAYER_LUA=core CORE_BUILD=$(cd ../../.. && pwd)/build
./make_media.sh && ./up.sh                    # test audio, broker, fake audio
python3 test_backend.py && python3 test_bedtime.py && python3 test_net.py
python3 test_security_backend.py && python3 e2e.py && python3 test_security.py
python3 test_spotify.py && python3 test_robustness.py && python3 test_loader.py
python3 test_httpd.py && python3 test_clock.py && python3 test_wifi_page.py
python3 ../../../core/spec/integration/endurance.py 3     # minutes (default 10, what nightly.yml runs)
```

What runs where: the suites above on every push to `main` and every pull request (CI job
*oracle*); the endurance run only in `nightly.yml` (every night and on release tags), for
10 minutes.

Each suite runs on its own as well as in this order: it builds its own fresh Jooki (`setup.sh`),
starts its own core and waits for it, and `test_security.py` deploys the page itself when `e2e.py`
did not run before it. `smoke.py` (the CI's *core* job) is the exception: it starts a core of its
own, so no bench core may be running (`pkill -f harness.lua`), and a fake audio left playing by a
suite counts against its idle-traffic budget (`pkill -f fake_audio.py`, then `./up.sh` again).

The unit specs run without any of this: `lua5.1 core/spec/run.lua` from the repository root.

## Writing a test

Two modules carry what the suites share; a suite keeps only its checks.

- `jk.py`, the client: `Jooki()` connects, subscribes and asks for the state until the core answers
  (it raises, with the end of the core's log, when it does not). `j.get("audio.nowPlaying.trackIndex")`
  reads the state; `j.pls`, `j.tracks`, `j.tokens`, `j.np`, `j.pb`, `j.maint`, `j.bt`, `j.nfc_state`
  are the usual parts. `j.newpl()`, `j.upload(..., wait=True)`, `j.v2()` send and wait.
- `bench.py`, the bench: `B.boot(seed=, ui=, pre=, config=)` (fresh Jooki + core + client),
  `B.restart(j)`, `B.Results()` (`check`, `expect`, `finish`), `B.Spy(topics...)` (what goes over the
  bus), the broker (`kill_brokers`, `start_broker`), the core's log (`log_mark`, `wait_log`,
  `check_clean_log`), `wait_line` for a child process.

No fixed sleep: wait for the thing the next line reads.

| The next line reads… | Write |
|---|---|
| a value the command sets | `j.wait(lambda: j.pls[p].get("star") == "Jooki.Fox")` or `j.wait_state("audio.playback.state", "PAUSED")`: raises `WaitTimeout` saying what it waited for and what the core shows |
| the same condition as the check | `R.expect("T2 …", lambda: …, 5, lambda: info)`: waits, then prints PASS/FAIL, never raises |
| something that may legitimately not come | `j.poll(cond, t)` / `B.poll(cond, t)`, then `check(...)` |
| nothing new in the state (a refusal, an ignored message) | `j.barrier()`: a full state asked after our messages, so they were all handled |
| what another bus client sends | `spy.mark()` before, `B.poll(lambda: spy.since(n, "/j/…"))` after |
| that something did NOT happen | `B.quiet(seconds, "why")`: the only sleep left, and it says why |

Two things to know about the state. The core sends whole top-level parts (`audio`, `bedtime`, `nfc`…),
at most every 0.25 s: the client replaces them, an empty part reads as `{}`. The full answer to
`GET_STATE` (what `barrier()` waits for) carries the same parts as the partial updates.
