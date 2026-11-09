# Turn off every device light

Settings offers two independent switches for the ring, side lights and heart:

- **Settings → Night mode → Turn off all lights at night** applies only while night mode is enabled and
  the current time is within its scheduled hours. The lights return to their
  current status at the end of the window, or immediately if night mode is
  disabled. This boolean `lights_off` is stored in `bedtime.json` and exposed as
  `bedtime.cfg.lights_off`, false by default. Use `OJ_BEDTIME_SET` or `bedtime.set`.
- **Settings → Turn off all lights permanently** applies all day, even with night mode
  disabled. It takes precedence over the schedule. This boolean `lights_off` is
  stored in `audiocfg.json`, false by default. Use `SET_CFG` or `device.set_config`.

Both preferences survive a restart and retain the existing parent-code protection.
Invalid types are rejected before any write. The permanent switch is in the main
settings, including when night mode is disabled; the timed switch belongs to the enabled night
settings. Dimming is disabled while either darkness preference is selected, but
its saved value is retained for when the lights are on again. The night-volume
slider and sleep timer remain independent.

Outside the startup cue, effective darkness is the permanent preference OR `limits.lights_off`, which
is true only during the scheduled night window. Changes to darkness trigger the
driver even if dimming and volume stay unchanged. Boot evaluates the saved
schedule and clock before issuing the first light commands. If darkness is requested,
normal startup status remains visible until Wi-Fi is associated and an IP address
is reported, followed by a ten-second countdown and
three 150 ms white flashes separated by 150 ms darkness, then the global driver
stays off. Night dimming also applies to these flashes. A broker reconnect or cable
change reapplies the current phase and never restarts the cue. A Wi-Fi disconnect
during the countdown cancels it; reconnecting starts a fresh ten seconds. After
the three flashes, later reconnections never replay the startup cue. A web light-setting
change cancels any pending cue. Without a valid
clock, scheduled darkness waits for time synchronisation; the permanent preference
still applies after the startup cue.

Short heart presses retain their configured next-song or pause/play action and
are handled immediately on release. There is no multi-click light gesture and
no temporary physical override of the saved lighting preferences.

Manual shutdown through the heart’s long press or the web page flashes red three
times, even in darkness, and then shuts down without an acknowledgement sound.
Music output is temporarily held at zero without changing the saved volume. The
cue cancels any pending startup countdown and ignores further button input;
no fourth red shutdown indicator is appended. Protective low-battery shutdown and
host termination bypass this optional manual cue and retain their existing paths.

The existing Holtek controller interface switches its global LED driver:
`/j/ht/output/raw_write`, `34 0` to disable it and `34 8` to enable it. No ESP32
firmware update is required. The core subscribes to the read-back response,
`/j/ht/input/raw_read_response`, and checks the register and value. A missing or
incorrect answer gets at most three attempts, including the initial write.

After the startup cue, the setting cancels the Wi-Fi and party animations and
prevents ordinary event/error colours. The three red manual shutdown flashes are
an explicit exception. Battery monitoring and protective shutdowns continue. Darkness
is reapplied after its startup cue, after a bus reconnect and after cable / charging transitions.
When both sources of darkness are inactive, the core repaints the current status
and resumes the Wi-Fi animation when needed. A brief light before the application
starts remains possible.

Tests: `core/spec/lights_cue_spec.lua` covers connected startup timing, cue
cancellation, immediate short presses, manual shutdown flashes and protective
shutdown paths. `tools/openjooki/tests/test_lights_cues.py` checks actual bus timing,
exactly three startup flashes and normal rapid heart presses without changing
lighting preferences. `test_shutdown_lights.py` checks both manual power-off paths
with the real core while intercepting the actual poweroff syscall. The existing
light-control and German browser suites cover independent saved preferences,
parent protection, controller read-back and narrow layouts.

On a Jooki 2 running OpenJooki 2.4.21, controller read-back confirmed scheduled
darkness, daytime restoration, the permanent override, disabling night mode and
persisted scheduled darkness after a full reboot. The original night hours,
volume and light preferences were restored after the checks. The owner previously
confirmed that the global gate visibly turns off the ring, both side lights and
heart; the scheduled checks verify that same gate through controller read-back.

The final code is installed on the physical Jooki alongside the current upstream
Softvol change. The speaker PCM opened successfully; API 2 volumes 5/15/25 and
mute had correct mixer/ESP32 read-back. The owner confirmed clean sound, audible
volume changes and silence at zero. These checks establish API 2 compatibility,
not stock-firmware speaker gain. The connected startup and silent shutdown cues
pass the real-core bench; their final visible behavior after a full physical
power cycle remains to be confirmed. ESP32 firmware remains unchanged.

Two guards on the cues: without a usable Wi-Fi address the startup cue waits at most a minute
(`lights.NO_WIFI_S`), so a Jooki away from home or in airplane mode still goes dark. After the red
power-off flashes the driver is written back to `34 8`, unless darkness was requested, because the
heart is also the charging light of a Jooki switched off.
