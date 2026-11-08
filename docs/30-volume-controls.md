# Persistent web volume and one scale for parent limits

The core and ESP32 keep the last physical dial position separately from the
requested volume. The first reading establishes a baseline; repeated readings
leave a saved web request alone. An actual movement takes over again. A web
request above a low dial position therefore remains effective until the dial moves.

## One global scale

`toy_safe_maxvol` is an integer from 0 to 100 in `audiocfg.json`. Its slider sits
below kids mode in the main settings and is disabled outside kids mode or without
ESP32 volume API 2. The night-volume slider remains in Night mode. Both use the
same global volume curve: kids 40 and night 30 produce a ceiling of 30; kids 20
and night 30 produce 20. These percentages are positions on the existing
logarithmic volume curve, not percentages of acoustic power.

The new parent setting replaces the fixed factory kids attenuation. There is no
second multiplier after applying the two limits. The initial ceiling is **56%**,
the highest integer on the global speaker curve whose gain does not exceed the
factory kids maximum (normal factor 1.5, factory kids factor 0.2). Earlier relative
parent limits migrate conservatively to this scale once; an internal migration
marker prevents repeated conversion. Explicitly selecting 100 allows the full
global range. Changing a ceiling never overwrites the saved requested volume.

Effective output is `min(requested, kids maximum if enabled, night maximum)`
followed by the sleep fade. Mute and temporary streaming silence force zero.
`SET_CFG` and `device.set_config` validate integer limits before writing and keep
the existing parent-code protection. Limit and kids-mode changes apply immediately.

## Firmware and output paths

The additive `SetVolume` command and `volume_api=2` capability are described in
[the build instructions](../tools/firmware/README.md). Existing protobuf command
numbers and tags remain unchanged. Unsupported firmware receives no new command;
the UI explains why the new parent slider is unavailable.

Speaker and Bluetooth volume are applied in the ESP32 under one volume lock.
The global curve and transmitted ceiling also apply to actual dial movement
before Linux responds. Periodic sampling cannot replace the selected web value.
Legacy SetToysafe users retain the factory curve; SetVolume explicitly opts into
the global curve. Hardware mute remains effective.

Wired headphones retain the ALSA path. The core first sets the bounded output,
then bypasses the fixed ALSA kids multiplier when global volume is supported.
It caches that mode through fade ticks and reapplies it after factory kids-mode
scripts. Failure to change the mixer mode is logged and retried on a later apply.
Startup, mute/unmute, fades, temporary silence and output switches use the same
volume-command path.

## Verification on 2026-11-08

| Check | Result |
|---|---|
| Isolated volume-branch Lua specs | 341 passed |
| Isolated real-core/MQTT/Chromium volume checks | 29 passed |
| Isolated backend / bedtime / UPnP regressions | 63 / 24 / 78 passed |
| Boot/API and resource budgets | 11 passed; idle 0.50 messages/s, RSS 4872 KiB |
| Native firmware | All 101 values and ceilings, startup ordering, repeated ADC samples, actual movement, mute and invalid requests pass |
| Actual ESP32 gain functions | All 101 global levels identical with kids mode on/off; factory default, legacy fallback, ceiling, mute and lock failures pass under sanitizers |
| Actual Linux protocol codec | Legacy/API 1/API 2, omitted/zero limits, malformed replies, errors and missing responses pass under sanitizers |
| Protobuf compatibility | Every existing message number and field tag preserved |
| Reproducible builds | Two independent ESP32 images/ELFs and MIPS controllers match byte for byte; packages reproduce |
| Original physical recovery | Complete 16 MiB private backup verified; stock restoration via cold UART boot physically rehearsed and verified |
| Preliminary hardware trial | Earlier API 1 SDK port boots with working Wi-Fi; real volume acknowledgments, unchanged dial reports and parent limits tested, then stock restored |
| Global API 2 device trial | Real command acknowledgments, unchanged physical wheel reports, parent/night limits, invalid inputs, mute/fade and full reboot passed |
| Audible speaker and actual wheel takeover | Confirmed by the device owner |
| Wired headphones / Bluetooth audio | Not yet tested on the physical device |

Tested image hashes, source details and remaining device checks are in
[the SDK port report](31-public-sdk-port.md). The browser bench uses an answering
hardware peer; successful protocol replies alone do not establish audible gain.
Linux A/B rollback does not restore ESP32 flash or NVS. Both recovery layers are
required for a firmware trial.
