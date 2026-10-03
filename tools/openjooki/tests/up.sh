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
for i in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/1883) 2>/dev/null && break; sleep 0.1; done   # the broker listens
pgrep -f "^python3 fake_audio" >/dev/null || (setsid python3 fake_audio.py >/tmp/fakeaudio.log 2>&1 < /dev/null &)
for i in $(seq 1 50); do grep -q connected /tmp/fakeaudio.log 2>/dev/null && break; sleep 0.1; done  # the fake audio is on the bus
pgrep -af "^mosquitto|^python3 fake_audio"
