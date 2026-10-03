#!/bin/bash
# start the core (built in $CORE_BUILD or ../../../build). The only argument still accepted is "core":
# the 1.x patched program left with ADR-0012.
pkill -f "^lua5.1 run" 2>/dev/null; pkill -f "harness.lua" 2>/dev/null
# like the device's launcher: the next core starts once the previous one has really exited
# (its shutdown saves its files), 5 s at most
for i in $(seq 1 25); do pgrep -f "harness.lua|^lua5.1 run" >/dev/null || break; sleep 0.2; done
# ... and has let go of its web port: a script it started in the background inherits the listening
# socket and may outlive it, and the new core would then find the port taken (its page down until
# its own retry). Wait for the port (5 s at most); after 1 s, stop whoever still holds it.
P="${OJ_HTTP_PORT:-8090}"
for i in $(seq 1 25); do
  (exec 3<>/dev/tcp/127.0.0.1/$P) 2>/dev/null || break
  [ "$i" = 5 ] && for p in $(ss -ltnpH "sport = :$P" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2); do kill "$p" 2>/dev/null; done
  sleep 0.2
done
cd "$(dirname "$0")"
LUA="${1:-${PLAYER_LUA:-core}}"
[ "$LUA" = "core" ] || { echo "start_player.sh: only the core runs on the bench (got '$LUA')"; exit 2; }
# OJ_HTTP_PORT: the web server on an unprivileged port on the bench (no root); the device uses the default 80.
# OPENJOOKI_CONFIG: a JSON of config overrides for this core (kernel.config), e.g. the update addresses in e2e.py
ENVS="JOOKI_LOG_LEVEL=${LOGLVL:-info} id=bench hostname=jooki-bench.local ip=10.0.0.2 wifi_mac=00:11:22:33:44:55 machine=ml-j2000 firmware=bench wlan_interface=lo OJ_HTTP_PORT=${OJ_HTTP_PORT:-8090} OPENJOOKI_CONFIG=${OPENJOOKI_CONFIG:-}"
B="${CORE_BUILD:-$(cd ../../.. && pwd)/build}"
N=$(grep -c '^READY' /tmp/player.log 2>/dev/null)
env $ENVS lua5.1 "$B/harness.lua" "$B/core.lua" >> /tmp/player.log 2>&1 &
# back once the new core says READY (10 s at most); it connects to the broker right after (bench.py waits for that too)
for i in $(seq 1 50); do c=$(grep -c '^READY' /tmp/player.log 2>/dev/null); [ "${c:-0}" -gt "${N:-0}" ] && break; sleep 0.2; done
tail -n 3 /tmp/player.log
