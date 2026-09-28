#!/bin/bash
# start bench services (idempotent)
cd "$(dirname "$0")"
# the broker's WebSocket (8000) needs a password, like the device (docs/adr/0007).
# Mirror what /etc/rcS.d/S57_oj-security.sh does: a passwd file the broker reads,
# and oj-auth.json served to the page. The bench uses a fixed credential.
mosquitto_passwd -c -b /tmp/oj_passwd jooki benchsecret 2>/dev/null || \
  printf 'jooki:benchsecret\n' > /tmp/oj_passwd   # plain fallback if mosquitto_passwd is absent
# mosquitto drops to its own user and must be able to read it (hash only)
chmod 640 /tmp/oj_passwd; chown mosquitto /tmp/oj_passwd 2>/dev/null || chmod 644 /tmp/oj_passwd
pgrep -f "^mosquitto -c" >/dev/null || (setsid mosquitto -c mosquitto.conf >/tmp/mosq.log 2>&1 < /dev/null &)
pgrep -f "^python3 webctrl_emu" >/dev/null || (setsid python3 webctrl_emu.py 8080 >/tmp/webctrl.log 2>&1 < /dev/null &)
sleep 1
pgrep -f "^python3 fake_audio" >/dev/null || (setsid python3 fake_audio.py >/tmp/fakeaudio.log 2>&1 < /dev/null &)
sleep 0.5; pgrep -af "^mosquitto|^python3 webctrl|^python3 fake_audio"
