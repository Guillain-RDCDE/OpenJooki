# ADR-0008 — No shell processes or temp files in the loop

Status: proposed (2026-09-26)

## Context
Measured on our Jooki (docs/22 §3.3): the old program starts about three
shell processes per second while idle (`test -e` for a flag, `wifi_ip.sh`,
plus `arping` every 30 s) and each `sys.execute` writes and reads two
temporary files; the root filesystem is mounted `sync` and `/tmp` is on it.
That is ~8 synchronous flash writes per second for nothing, on a 27 MB
device with a memory card.

## Decision
- The kernel and the services never spawn a process on a timer. Facts that
  change (IP, Wi-Fi status, plugged, battery) come from **events** the daemons
  already publish, or from reading `/sys` and `/proc` files directly.
- `adapters.shell` exposes **named actions** only (`probe_audio`, `set_lang`,
  `toysafe_update`, `poweroff`, `reboot`, `factory_reset`, `wifi_add`,
  `speak_info`, `update_start`), each with its allowed arguments; output goes
  to a pipe (`io.popen`), never to a temp file; anything that must write goes
  to `/run` (tmpfs).
- A budget test counts process spawns on the bench during a 10-minute
  scripted session: the allowed number is the number of user actions that
  legitimately need one.

## Alternatives
- **Keep the scripts, call them less often**: still processes, still temp
  files, still untestable behaviour hidden in shell.
- **Rewrite the shell scripts in Lua**: for most of them, yes over time (they
  are small); for `ml-audio-probe-wrapper.sh` (ffprobe) and system actions
  (poweroff), a process is the right tool — once, on a user action.

## Consequences
- Fewer moving parts and less flash wear; measurable in the budget test.
- The IP is taken from the `dhcp.bound/renew` events and `/sys/class/net`
  reads on a slow timer (60 s), not from a script every second.
