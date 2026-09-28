#!/bin/ash
# OpenJooki security bootstrap (docs/adr/0007-security-model).
#
# Gives the broker a per-Jooki password on its network (WebSocket) listener,
# generated once at first boot and kept across updates. Local clients (the core
# and the closed hardware daemons) stay anonymous on 127.0.0.1, so nothing on
# the device has to change. The password is served to the page at /oj-auth.json,
# which web_ctrl returns without CORS: the page reads it at its own origin, a
# booby-trapped website cannot, and JSON is not runnable as a <script>.
#
# Installed as /etc/rcS.d/S57_oj-security.sh so it runs BEFORE the broker (S58):
# the password file therefore exists before mosquitto reads it, with no window
# where the WebSocket is open. It is also safe to run by hand after a settings
# change: it restarts the broker only when the broker is already running.
set -u

D=/data/openjooki
SECRET="$D/ws_secret"
CONF=/etc/mosquitto/mosquitto.conf
BASE="$CONF.openjooki-base"
PW=/etc/mosquitto/passwd
AUTH=/jooki/app/www/public/oj-auth.json
LANFLAG="$D/mqtt_lan"
USER=jooki
MARK="# --- openjooki: network mqtt (added at runtime) ---"

mkdir -p "$D" 2>/dev/null

# 1. the per-Jooki secret: generated once, kept across A/B updates (/data is p5)
if [ ! -s "$SECRET" ]; then
  if command -v openssl >/dev/null 2>&1; then
    S=$(openssl rand -hex 24)
  else
    S=$(dd if=/dev/urandom bs=1 count=999 2>/dev/null | md5sum | cut -c1-32)
    S="$S$(dd if=/dev/urandom bs=1 count=999 2>/dev/null | md5sum | cut -c1-16)"
  fi
  printf '%s\n' "$S" > "$SECRET.tmp" && mv "$SECRET.tmp" "$SECRET"
  chmod 600 "$SECRET"
fi
PASS=$(head -n 1 "$SECRET" 2>/dev/null)
[ -n "$PASS" ] || { logger -t oj-security "no secret available; broker left as shipped"; exit 0; }

# 2. broker password file (only the 8000 WebSocket listener uses it).
#    mosquitto 1.6 wants -c BEFORE -b (order matters); it holds only a hash, and
#    the broker drops to the "mosquitto" user, so give that user read access.
if command -v mosquitto_passwd >/dev/null 2>&1; then
  if mosquitto_passwd -c -b "$PW.tmp" "$USER" "$PASS" 2>/dev/null; then
    chmod 640 "$PW.tmp"
    chown mosquitto "$PW.tmp" 2>/dev/null || chmod 644 "$PW.tmp"
    mv "$PW.tmp" "$PW"
  fi
fi

# 3. the page reads this at the same origin (see the header)
printf '{"mqttUser":"%s","mqttPass":"%s","wsPort":8000}\n' "$USER" "$PASS" > "$AUTH.tmp" 2>/dev/null \
  && { chmod 644 "$AUTH.tmp"; mv "$AUTH.tmp" "$AUTH"; }

# 4. keep a pristine copy of the shipped config, then rebuild the live config from it
[ -f "$BASE" ] || cp "$CONF" "$BASE" 2>/dev/null
cp "$BASE" "$CONF.tmp" 2>/dev/null || cp "$CONF" "$CONF.tmp"

# 5. optional: MQTT on the LAN for home automation (off by default). A listener
#    bound to the Wi-Fi IP only, password required; the localhost anonymous
#    listener is untouched, so the closed daemons keep working.
if [ -f "$LANFLAG" ]; then
  IP=$(ip -4 -o addr show 2>/dev/null | grep -v ' lo ' | grep -oE 'inet [0-9.]+' | sed 's/inet //' | head -n 1)
  if [ -n "$IP" ]; then
    { echo ""; echo "$MARK"; echo "listener 1883 $IP"; echo "protocol mqtt"; \
      echo "allow_anonymous false"; echo "password_file $PW"; } >> "$CONF.tmp"
  else
    logger -t oj-security "network mqtt requested but no LAN IP yet"
  fi
fi
mv "$CONF.tmp" "$CONF" 2>/dev/null

# 6. a settings change (not the boot path): the broker is already up -> reload it
if [ -f /var/run/mosquitto.pid ] && kill -0 "$(cat /var/run/mosquitto.pid 2>/dev/null)" 2>/dev/null; then
  /etc/init.d/mosquitto restart >/dev/null 2>&1 || true
fi
exit 0
