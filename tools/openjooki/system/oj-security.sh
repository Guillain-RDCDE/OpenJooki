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
  # the Wi-Fi IP: `ip` lives in /sbin and is not on the boot PATH; the route's src is
  # the address other devices reach us on (same trick as /jooki/app/services/wifi_ip.sh)
  IP=$(/sbin/ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
  if [ -n "$IP" ]; then
    { echo ""; echo "$MARK"; echo "listener 1883 $IP"; echo "protocol mqtt"; \
      echo "allow_anonymous false"; echo "password_file $PW"; } >> "$CONF.tmp"
  else
    logger -t oj-security "network mqtt requested but no LAN IP yet"
  fi
fi
CHANGED=1
cmp -s "$CONF.tmp" "$CONF" 2>/dev/null && CHANGED=0
mv "$CONF.tmp" "$CONF" 2>/dev/null

# 6. a settings change (not the boot path): the broker is already up -> restart it with
#    the new config, only if the config changed. This device daemonizes mosquitto with -d,
#    keeps no pidfile and has no working init.d, so restart by hand (mirrors
#    /etc/rcS.d/S58_mosquitto.sh). At boot S57 runs before S58, so nothing is running yet
#    and this is skipped.
#    The hardware controllers (tokens and knobs, buttons, lights) leave "cleanly" (exit 0)
#    when the broker goes, and their launcher only restarts a crash: without them the
#    Jooki is deaf until the next restart (#28, the same as adapters.broker_watch knows).
#    So wait until they are gone and start them again, as ml-start-app.sh starts them.
MPID=$(ps 2>/dev/null | grep '[m]osquitto -c' | awk '{print $1}' | head -n 1)
if [ -n "$MPID" ] && [ "$CHANGED" = 1 ]; then
  CTRL="gpio_ctrl:-5 ht_ctrl:-1 esp32_ctrl:-5"
  L=/jooki/bin/ml-launch-controller.sh
  # a launcher's command line, read from /proc (busybox ps may cut long lines)
  launcher_alive() {
    for f in /proc/[0-9]*/cmdline; do
      case "$(tr '\000' ' ' 2>/dev/null < "$f")" in *"ml-launch-controller.sh /jooki/bin/$1 "*) return 0 ;; esac
    done
    return 1
  }
  OLD=""
  for c in $CTRL; do OLD="$OLD $(pidof "${c%%:*}" 2>/dev/null)"; done
  kill "$MPID" 2>/dev/null
  # the controllers on the old broker see it close and leave at once: wait for them (10 s at most)
  i=0
  while [ $i -lt 10 ]; do
    left=0
    for p in $OLD; do kill -0 "$p" 2>/dev/null && left=1; done
    [ $left = 0 ] && break
    sleep 1; i=$((i+1))
  done
  rm -f /var/run/mosquitto.pid 2>/dev/null
  /usr/sbin/mosquitto -c "$CONF" -d </dev/null >/dev/null 2>&1
  # a controller still running, or a launcher still alive (it starts a crashed one again by itself),
  # needs nothing; a launcher alone is between two states (a crash: it starts it again in 1 s; a
  # clean exit: it ends): wait for one or the other. Only a controller with no launcher is started.
  n=0
  for c in $CTRL; do
    b=${c%%:*}
    i=0; start=0
    while [ $i -lt 10 ]; do
      pidof "$b" >/dev/null 2>&1 && break
      launcher_alive "$b" || { start=1; break; }
      sleep 1; i=$((i+1))
    done
    if [ $start = 1 ] && [ -x "$L" ] && [ -x "/jooki/bin/$b" ]; then
      "$L" "/jooki/bin/$b" "${c#*:}" </dev/null >/dev/null 2>&1 &
      n=$((n+1))
    fi
  done
  logger -t oj-security "broker restarted for the network mqtt setting; controllers started again: $n"
fi
exit 0
