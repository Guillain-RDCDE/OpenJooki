#!/bin/bash
# start the Lua app (arg: lua source file, or "core" for the 2.0 core built in $CORE_BUILD or ../../../build)
pkill -f "^lua5.1 run" 2>/dev/null; pkill -f "harness.lua" 2>/dev/null; sleep 0.3
cd "$(dirname "$0")"
LUA="${1:-${PLAYER_LUA:-player.patched.lua}}"
ENVS="JOOKI_LOG_LEVEL=${LOGLVL:-info} id=bench hostname=jooki-bench.local ip=10.0.0.2 wifi_mac=00:11:22:33:44:55 machine=ml-j2000 firmware=bench wlan_interface=lo"
if [ "$LUA" = "core" ]; then
  B="${CORE_BUILD:-$(cd ../../.. && pwd)/build}"
  env $ENVS lua5.1 "$B/harness.lua" "$B/core.lua" >> /tmp/player.log 2>&1 &
else
  env $ENVS lua5.1 run.lua "$LUA" >> /tmp/player.log 2>&1 &
fi
sleep 1.5; tail -n 5 /tmp/player.log
