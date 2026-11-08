# Turn off every device light

Settings → Night mode → Turn off all device lights controls the ring, side lights
and the heart. This switch is available even when night mode is disabled: it
applies all day, independently of the schedule and the timed dimming setting.
`lights_off` is a boolean in `audiocfg.json`, false by default. It survives a restart
and can be set through `SET_CFG` or `device.set_config`, with the existing parent
code protection. Invalid types are rejected before any write.

The existing Holtek controller interface switches its global LED driver:
`/j/ht/output/raw_write`, `34 0` to disable it and `34 8` to enable it. No ESP32
firmware update is required. The core subscribes to the read-back response,
`/j/ht/input/raw_read_response`, and checks the register and value. A missing or
incorrect answer gets at most three attempts, including the initial write.

The setting cancels the Wi-Fi and party animations and prevents event, error and
shutdown colours. Battery monitoring and protective shutdowns continue. Darkness
is reapplied at boot, after a bus reconnect and after cable / charging transitions.
Turning it off repaints the current status and resumes the Wi-Fi animation when
needed. A brief light before the application starts remains possible.

Tests: `core/spec/lights_off_spec.lua` covers validation, parent code, persistence,
animation suppression, battery protection, read-back, bounded retries and restoring
colours. `tools/openjooki/tests/test_lights_off.py` runs the real core and browser
with an answering controller, including confirmation without retries, persistence
after a core restart, and switching from the night settings with the schedule
disabled. Controller simulation does not establish visible behaviour;
verify the result on a physical Jooki.
