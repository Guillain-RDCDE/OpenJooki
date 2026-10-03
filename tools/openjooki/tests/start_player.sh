#!/bin/bash
# start the core (built in $CORE_BUILD or ../../../build). The only argument still accepted is "core":
# the 1.x patched program left with ADR-0012.
pkill -f "^lua5.1 run" 2>/dev/null; pkill -f "harness.lua" 2>/dev/null; sleep 0.3
# like the device's launcher: the next core starts once the previous one has really exited
# (its shutdown saves its files), 5 s at most
for i in $(seq 1 25); do pgrep -f "harness.lua|^lua5.1 run" >/dev/null || break; sleep 0.2; done
cd "$(dirname "$0")"
LUA="${1:-${PLAYER_LUA:-core}}"
[ "$LUA" = "core" ] || { echo "start_player.sh: only the core runs on the bench (got '$LUA')"; exit 2; }
# OJ_HTTP_PORT: the web server on an unprivileged port on the bench (no root); the device uses the default 80.
# OPENJOOKI_CONFIG: a JSON of config overrides for this core (kernel.config), e.g. the update addresses in e2e.py
ENVS="JOOKI_LOG_LEVEL=${LOGLVL:-info} id=bench hostname=jooki-bench.local ip=10.0.0.2 wifi_mac=00:11:22:33:44:55 machine=ml-j2000 firmware=bench wlan_interface=lo OJ_HTTP_PORT=${OJ_HTTP_PORT:-8090} OPENJOOKI_CONFIG=${OPENJOOKI_CONFIG:-}"
B="${CORE_BUILD:-$(cd ../../.. && pwd)/build}"
env $ENVS lua5.1 "$B/harness.lua" "$B/core.lua" >> /tmp/player.log 2>&1 &
sleep 1.5; tail -n 5 /tmp/player.log
