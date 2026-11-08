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

The effective darkness is the permanent preference OR `limits.lights_off`, which
is true only during the scheduled night window. Changes to darkness trigger the
driver even if dimming and volume stay unchanged. Boot evaluates the saved
schedule and clock before issuing the first light commands. Without a valid
clock, scheduled darkness waits for time synchronisation; the permanent preference
still applies.

The existing Holtek controller interface switches its global LED driver:
`/j/ht/output/raw_write`, `34 0` to disable it and `34 8` to enable it. No ESP32
firmware update is required. The core subscribes to the read-back response,
`/j/ht/input/raw_read_response`, and checks the register and value. A missing or
incorrect answer gets at most three attempts, including the initial write.

The setting cancels the Wi-Fi and party animations and prevents event, error and
shutdown colours. Battery monitoring and protective shutdowns continue. Darkness
is reapplied at boot, after a bus reconnect and after cable / charging transitions.
When both sources of darkness are inactive, the core repaints the current status
and resumes the Wi-Fi animation when needed. A brief light before the application
starts remains possible.

Tests: `core/spec/lights_off_spec.lua` covers validation, parent code, persistence,
animation suppression, battery protection, read-back, bounded retries and restoring
colours, both night-window boundaries, boot-time darkness, disabled schedules and
the permanent override. `tools/openjooki/tests/test_lights_off.py` runs the real core and browser
with an answering controller, including confirmation without retries, persistence
after a core restart, separate scheduled and permanent switches, saved dimming,
and switching from the main settings with the schedule disabled. Controller simulation does not establish visible behaviour;
verify the result on a physical Jooki.

On a Jooki 2 running OpenJooki 2.4.21, controller read-back confirmed scheduled
darkness, daytime restoration, the permanent override, disabling night mode and
persisted scheduled darkness after a full reboot. The original night hours,
volume and light preferences were restored after the checks. The owner previously
confirmed that the global gate visibly turns off the ring, both side lights and
heart; the scheduled checks verify that same gate through controller read-back.
