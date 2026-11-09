# Persistent web volume and one scale for parent limits

The core and ESP32 keep the last physical dial position separately from the
requested volume. The first reading establishes a baseline; repeated readings
leave a saved web request alone. An actual movement takes over again. A web
request above a low dial position therefore remains effective until the dial moves.

## On today's firmware, without flashing anything

Without `volume_api == 2` the ESP32 sets the speaker from its dial, and no command can raise it.
Since this change the speaker's audio also goes through a software control (`softvol_spk` in
`tools/openjooki/system/asound.conf`, the same `Softmaster` control as the headphones, 0.4 dB a
step like the dial). So the page, night mode, the sleep fade and mute can **lower** the speaker,
never raise it above the dial: mixer level = `100 - (dial - volume)`, 0 for silence.

- A request above the dial is saved as the dial's value: the page never shows a level the Jooki
  is not playing at. Wired headphones have no such ceiling: their level is the volume.
- An unchanged dial report leaves a saved request alone; moving the dial takes over.
- With `volume_api == 2` the ESP32 applies the volume and the mixer stays at 100.
- The kids slider below only shows with `volume_api == 2`.

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

Effective output is `min(requested, kids maximum if enabled and API 2, night maximum)`
followed by the sleep fade. Mute and temporary streaming silence force zero.
`SET_CFG` and `device.set_config` validate integer limits before writing and keep
the existing parent-code protection. Limit and kids-mode changes apply immediately.

The configurable kids maximum applies only after `volume_api == 2` is advertised.
With an unknown capability, legacy firmware or API 1, the core leaves the fixed
factory kids attenuation in charge instead of adding a second ceiling. For
example, requests of 80 and 100 remain 80 and 100 on the legacy ALSA path;
the sound chip still attenuates them in kids mode. Night limits, fades and mute
continue to apply on that path.

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

Capability changes and broker reconnection also reapply the policy without
requiring dial movement. When returning to legacy mode, factory headphone
attenuation is restored before a higher requested level is set. If that mixer
operation fails, wired output stays silent until a later apply succeeds.

## Verification on 2026-11-08

| Check | Result |
|---|---|
| Current branch Lua specs, including legacy headphone policy and mixer failures | 365 passed |
| Real-core/MQTT/Chromium volume checks, including legacy headphones and capability changes | 60 passed |
| Backend / bedtime / UPnP regressions | 63 / 31 / 78 passed |
| Boot/API and resource budgets | 11 passed; idle 0.30 messages/s, RSS 4920 KiB |
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

## Audition a settings maximum

The kids maximum in Settings and the maximum on the Night mode page each have a
**Test** button. There is no test button on the player's volume slider. The night
test works during the day, before the schedule starts (issue
[#9](https://github.com/Guillain-RDCDE/OpenJooki/issues/9)).

The Jooki plays a short, 660 Hz PCM tone lasting 0.8 seconds through its speaker or wired
headphone route; Bluetooth follows the speaker route through the ESP32. This uses
the same mixer and firmware volume command as music. The selected stored maximum
replaces the requested music volume for the audition; other active kids/night
ceilings and any fade still apply. The page shows the effective test percentage.
On stock firmware the physical dial remains the speaker's upper ceiling.

Playing music is muted and paused before the test level is applied. API 2 waits
for the controller's volume acknowledgments before starting the tone, and again
before continuing music at its previous requested volume. A separate `aplay`
process keeps audio_ctrl's file/radio loaded, so continuing a book does not rewind
or restart its chapter. Previously paused music stays paused. A transport action
or a moved volume control cancels the audition and takes over. A timeout, rejected
command, player failure or output change also clears the temporary level; failed
volume acknowledgments leave music paused.

Neither the requested music volume nor any settings are written by a test.
`device.test_volume {target:"kids"|"night"}` (v2) and `OJ_VOLUME_TEST` (v1) are
protected by the parent code. The UI offers the buttons only on a core advertising
`audio.volume_test`; the configurable kids maximum still requires API 2. Busy or
muted playback returns a translated message instead of unmuting the Jooki.

The tone is generated locally by `tools/openjooki/make_volume_tone.py`, packaged
with the device UI, and uses no downloaded sound or browser audio. Its cosine ramps
avoid abrupt edges. `volume_test_spec.lua` covers caps, acknowledgments, both API
versions, cancellation and restoration. `test_volume_test.py` runs the real core
with MQTT/PCM peers and Chromium, including daytime tests, stock fallback, parent
protection, player failure and the German UI at 390 px. These peers verify the
control path; a physical listening test verifies audible output.

The API-2 device trial passed at 5%, 15% (with a smaller parent ceiling), and 0%.
The real tone player exited successfully, every volume command was acknowledged,
and Spotify continued on the same title after the test. The owner confirmed that
both UI buttons produce the expected tone and resume music correctly. Wired
headphone and Bluetooth tone output have not been physically auditioned.
