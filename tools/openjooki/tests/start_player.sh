#!/bin/bash
# start the Lua app (arg: lua source file)
pkill -f "^lua5.1 run" 2>/dev/null; sleep 0.3
cd "$(dirname "$0")"
env JOOKI_LOG_LEVEL=${LOGLVL:-info} id=bench hostname=jooki-bench ip=10.0.0.2 wifi_mac=00:11:22:33:44:55 machine=ml-j2000 firmware=bench wlan_interface=lo \
  lua5.1 run.lua "${1:-${PLAYER_LUA:-player.patched.lua}}" >> /tmp/player.log 2>&1 &
sleep 1.5; tail -n 5 /tmp/player.log
