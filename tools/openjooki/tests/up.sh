#!/bin/bash
# start bench services (idempotent)
cd "$(dirname "$0")"
pgrep -f "^mosquitto -c" >/dev/null || (setsid mosquitto -c mosquitto.conf >/tmp/mosq.log 2>&1 < /dev/null &)
pgrep -f "^python3 webctrl_emu" >/dev/null || (setsid python3 webctrl_emu.py 8080 >/tmp/webctrl.log 2>&1 < /dev/null &)
sleep 1
pgrep -f "^python3 fake_audio" >/dev/null || (setsid python3 fake_audio.py >/tmp/fakeaudio.log 2>&1 < /dev/null &)
sleep 0.5; pgrep -af "^mosquitto|^python3 webctrl|^python3 fake_audio"
