# The lights, the battery, the USB-C port

What the Jooki 2 shows with its lights, what its battery and charging port are,
and what to do when it no longer lights up. Compiled from two kinds of
sources, always named: the Jooki's own programs (read from the firmware of
December 2022, and from OpenJooki's core, whose light code has unit specs), and
what the r/jooki community found by opening their Jookis. Where something is
only reported and not measured on our Jooki, the page says so.

## 1. Who drives which light

The Jooki 2 has four groups of lights: the **ring** around the top plate, the
**heart** (the round button), and two **side dots**, one under each arrow
(`RING`, `CIRCLE`, `PREV`, `NEXT` on the bus; the volume buttons have their own
`VOL_INC`, `VOL_DEC`). Two programs share them:

- **the light controller** (`ht_ctrl`, closed, on the I²C "HT" chip): it reads
  the battery through the power-management chip (`/dev/ht_pmic`): voltage,
  percentage, **temperature**, cable in, charging, charging error. It publishes
  them on the bus (`/j/power/input/{battery_level,plugged_in,charging,charging_error}`)
  and keeps its own five charge states (`BAT_NUL`, `BAT_LOW`, `BAT_DEC`,
  `BAT_INC`, `BAT_FUL`). **The heart while charging is its business alone**:
  the application never sets it, and OpenJooki does not change it;
- **the application** (Muuselabs' `player`, or OpenJooki 2): the ring, the side
  dots and the heart at power-off. OpenJooki 2 keeps the original light language
  ([22-core-inventory.md](22-core-inventory.md) §3.7, `core/services/device.lua`),
  with one addition for the battery.

## 2. What the lights mean

### 2.1 Every day (same on 1.x and OpenJooki 2)

| What you see | What it means |
|---|---|
| heart white | on. The heart is lit by the controller as soon as the Jooki has power, before Linux has started: a white heart alone proves nothing about the rest (§5) |
| heart green | charging (§2.2) |
| ring white | on; idle, or playing something started from the page |
| ring **off** while music plays | a token is playing. By design (Muuselabs' code turns the ring off when a token is on), not a fault |
| both side dots white | connected to the Wi-Fi, with an address |
| left dot orange | not associated to a Wi-Fi network |
| right dot orange | associated, but no address yet (waiting for the router) |
| **both side dots orange, glowing left↔right** | **OpenJooki 2.1.1+**: waking up, looking for Wi-Fi at start-up (the chip takes ~1 min, docs/20). Tokens and music already work; the glow stops on its own once the network is found or you play something |
| **both side dots orange, steady** | no Wi-Fi (after start-up). Tokens and music still work; only the page and uploads need the network. See [20-network-health.md](20-network-health.md) (the chip is sticky and 2.4 GHz only; rescue over Bluetooth). If it stays orange on a network that used to work, it may be in **airplane mode**: see the knob trick below |
| side dots light blue, steady | a token was just recognised, or a track is starting |
| side dots light blue, one pulse | a phone or computer just opened the page |
| side dots green, eight pulses | a blank token was written (`Evt.Character.Write`) |
| side dots yellow, one pulse | a warning: kids-safe volume switched on or off, factory mode switched. **OpenJooki 2 only**: airplane mode switched on, battery under 20 % (every five minutes), and one minute before switching off for inactivity |
| side dots red, two pulses | an error: the token's playlist is empty, the memory card is full, Spotify or Deezer failed |
| **side dots red, steady, right after start-up** | 1.x only: the Jooki is in **airplane mode** (Wi-Fi and Bluetooth off). The original program's light code has no case for `Evt.Airplane.*` and lands on its "unknown event" branch, which is steady red; with the radios off nothing comes to repaint the dots. Owners read it as a dead Jooki ("the two side lights turn red and the app no longer connects"). The knob trick below switches the radios back on. OpenJooki 2 shows a yellow pulse instead, then the orange dots |
| everything off, heart red | switching off: heart held two seconds, *Turn off* on the page, fifteen minutes without activity on battery, or battery under 10 % |
| everything off, heart dim orange | suspend (a code path of the original program; not seen on a Jooki 2) |
| everything at about 5 % brightness | night mode (OpenJooki bedtime, [19-bedtime.md](19-bedtime.md)) |
| all lights blue at once, then off | Jooki 1 only: factory mode toggled from the buttons (`factory_reset.sh`) |
| all lights pulse yellow, then stay yellow | Jooki 1 only: factory reset in progress from the buttons |

Sounds go with only a few of these: the start-up chime (`Evt.Jooki.Ready`), a
short bleep when a token is written or a page connects, and three factory
voices ("factory mode" on and off, "production finished"). **A low battery
makes no sound**, and on the original program it makes no light either: the
app used to show "Jooki's battery is getting low", and the Jooki simply
switches itself off under 10 %. OpenJooki 2 adds the yellow pulse.

**Airplane mode and the knob.** The Wi-Fi and Bluetooth can be switched off
from the Jooki itself (a system token, or the buttons: the button daemon
`gpio_ctrl` reports `airplane_mode_on` / `airplane_mode_off` for a knob
gesture, and the program acts once it is held five seconds). Both side dots
then stay orange for good (steady red on 1.x right after start-up), which
looks like a fault. The way back, found by owners after Muuselabs' support had
given it to them
([r/jooki, December 2024](https://www.reddit.com/r/jooki/comments/1hpeg54/issue_with_2_solid_orange_lights_wifi_wont/)):
switch the Jooki off, **hold the track knob turned to *Next*** (to the right)
while switching it on, and keep it there until the start-up chime. Muuselabs'
guide says the same in one line: "Wi-Fi can be disabled or enabled during
start-up via the track knob while holding the heart button". On OpenJooki's
page, Settings shows the Wi-Fi state and lets you add a network.

**Airplane mode from the page (OpenJooki 2).** Parents asked for the button the
Muuselabs app had: no radio next to the bed, or on a plane. Settings → *Airplane
mode* switches the Wi-Fi and the Bluetooth off, but never for good: you pick how
long (a few hours, until the morning, or until the Jooki is switched off and on
again), the Jooki switches them back on by itself at that time, and in every case
its next start brings them back. The page loses the Jooki meanwhile, on purpose;
it says so and tells you when the Wi-Fi returns, instead of "the Jooki is not
answering". Tokens and music carry on. Under the hood: the radios go off through
the same `radio.sh` as the knob; a flag `OJ_AIRPLANE` in `/data/mode` marks the
bounded mode, a timer ends it, and at boot the program sees the flag, waits three
seconds after the chime and switches the radios back on, whatever the ESP32
remembers (it keeps airplane mode in its own memory, which is why the knob
version survives restarts). The knob gesture and the system tokens still switch
the radios for good, and they cancel a bounded mode when used.

### 2.2 The heart while charging

The controller owns it. Off the charger the heart is **white**. Muuselabs' own
description, in their charging notice of May 2024 (§4): once the cable is in,
**the heart turns green, solid or blinking**; and a Jooki that is off **powers
itself on** when the cable is plugged in. The community's reading of the two:
blinking green = charging, solid green = full. A reviewer (Newsweek, 2022)
described the heart **cycling green, white and red** as the low-battery sign;
we have not measured that one. Some owners also speak of "the typical red
light" when the cable goes in, so red on the charger exists too (the
controller's `BAT_LOW` state is the likely candidate: a nearly empty cell being
charged). The controller also has a *charging error* state: it publishes
`charging_error`, and its log line "Resetting charger error timer" says it
retries after a delay. Two owners described a heart that "blinks once or twice
then turns off" on the charger, with the Jooki not charging
([r/jooki, Inside your Jooki](https://www.reddit.com/r/jooki/comments/12r0y11/inside_your_jooki/));
that looks like this state. Check the cable and the port (§4) and the cell
(§3: a cell without its thermal sensor is refused).

Over SSH, the controller's own reading is in `/tmp/power_state.txt`, one line
like `4117 mV, 93.1%, 40000 mC, plugged:no, charging:no` (found by
u/HawaiianStyleBrah): voltage, charge, temperature in thousandths of a degree,
cable, charging.

### 2.3 During an update

- **OpenJooki**: the lights do nothing special. The page shows the steps
  (looking, downloading, checking, installing, restarting) and reconnects on its
  own; keep the Jooki plugged in. If the new system does not start, U-Boot goes
  back to the previous one at the next power-up ([15-ota-github.md](15-ota-github.md)).
- **Muuselabs' forced updater** (`ota2.sh`, 2021, still on the card): both side
  dots **yellow** while downloading or updating the ESP32, **red** when a
  download fails (it retries), **pink** while checking the file, rebooting to
  commit, and committing, **blue** while writing the partition, **green** when
  done, **red** at the end if a step failed. Its servers are gone, so today it
  can only fail: a Jooki 2 cycling yellow and red is trying to reach
  `my.jooki.rocks`. Restart it. The "purple and yellow on the left, then both
  green after a while" that owners saw during a factory reset in 2024 is most
  likely this table (pink reads as purple on the dots). Someone on r/jooki
  asked what a *Jooki 1* blinking pink means; we have no Jooki 1 to check.
- **Factory reset**: on a Jooki 2 it goes through `ht_trigger_factory_reset.sh`
  and U-Boot's `factory_reset` flag (boot the factory partition), a script we
  have not read; on a Jooki 1 the buttons at boot pulse all lights yellow four
  times, then leave them yellow while files are deleted, and all lights blue
  means factory mode was toggled. After a reset the original program says
  "factory mode" at start-up until that mode is switched off again (the
  original app did it; the flag is the file `/data/mode/FACTORY`, which
  OpenJooki 2 reads and ignores). OpenJooki 2 reuses the "factory mode off"
  voice for one thing: the confirmation when the parent code is cleared by
  holding both arrows for ten seconds.

## 3. The battery

**What it is.** A single lithium cell, 18650 format, with a **thermal sensor**
taped to the cell inside the pack and a protection circuit (three wires to the
board; photos of the open Jooki and of the pack, EU and US versions alike:
[r/jooki, Inside your Jooki](https://www.reddit.com/r/jooki/comments/12r0y11/inside_your_jooki/)). The original
pack, read by u/Open-Dig2504 from its label: `NLI-18650-1S1P`, cell
`1INR19/66`, 3.6 V, 2600 mAh, 9.36 Wh, 6.5 cm long
([r/jooki, Battery replacement](https://www.reddit.com/r/jooki/comments/1h71ily/battery_replacement/)).
Consistent with what the controller reports: voltage in mV, charge in tenths
of a percent, temperature in thousandths of a degree
(`{"mv":3900,"p":870,"t":31000}` on the bus). Muuselabs' user guide only says
"batteries are only to be replaced by authorized service personnel".

**What the program does with it** (identical in Muuselabs' program and in
OpenJooki 2, `core/kernel/config.lua`):

| Reading | Action |
|---|---|
| under 20 %, not charging | warning every five minutes (OpenJooki 2: yellow pulse) |
| under 10 %, not charging | the power-off sequence (heart red, then off) |
| **over 80 °C** | kids-safe volume forced on, volume set to 80, music paused, and the *overheat* voice message repeated every eight seconds (`power_overheat.sh`) until restart |
| cable plugged or unplugged | the USB port is switched between charging and headphones use; a cable sound in the original program |

**Signs of a worn cell**: the Jooki only works plugged in, or switches off
minutes after the cable is removed; a "daily charge" keeps it going for a while.

**Replacing it** (community, verified by several owners on the same thread,
[r/jooki, Replacement Battery](https://www.reddit.com/r/jooki/comments/1gekgjm/replacement_battery/)):

- seven Phillips screws under the Jooki; the shell opens without breaking;
- **the cell must have the thermal sensor**: a plain 18650 without it
  **does not charge** (u/fabianhuisman tried);
- what worked: a "Theradome LH40/LH80" replacement pack, INR18650 1S1P,
  2600 mAh (subtel.de) or 3400 mAh (123accu.nl), with a protection board and
  the thermal sensor; slightly longer than the original but it fits. The wires
  are spliced onto the original connector (photo of the original pack:
  [imgur](https://imgur.com/a/uIkYEeb)). Once done, the Jooki reports the
  battery temperature again;
- the other route, by u/Open-Dig2504: a bare 18650 with welding tabs, and the
  **original thermal sensor transplanted** onto it (clipped off the old cell,
  bridged with nickel strip and a small spot welder: never solder on a cell,
  it overheats the top of it), taped back into the old pack's wrapping. "It's
  amazing how long the battery lasts now";
- u/theartfuldodger42's first pack (a US listing, now gone) had no sensor and
  worked anyway, which is why the sensor question matters: the controller
  refuses to charge some cells and accepts others. Take one with the sensor:
  it is also what the over-80 °C protection above relies on.

Batteries are dangerous to work on; the people above say so themselves. (The
Jooki 1 also runs on an ordinary 18650 cell, `YC-INR18650`, per u/nv1t, who
opened one; its charging port and headphone jack sit on a small separate board
at the bottom, replaceable as a whole.)

**Where to see it**: OpenJooki's page, *Settings*: battery percentage, and
"charging" or "plugged in". The temperature is on the bus
(`/j/power/input/battery_level`), in the state (`power.level.t`) and in
`/tmp/power_state.txt` (§2.2); an owner reports the original web page showed
it after a battery swap.

## 4. The USB-C port and charging

**Muuselabs' notice (May 2024).** The last message the company sent to its
customers, kept on
[r/jooki](https://www.reddit.com/r/jooki/comments/1cklrry/update_on_jooki_charging_please_read_carefully/):
"an issue that can result in excessive heat at the USB-C port, when Jooki is
charging". Their instructions, worth keeping:

- no debris in the port, no damage to the cable, the plug fully inserted;
- **a charger of no more than 1 A**, and keep an eye on the Jooki while it
  charges;
- the check: with the Jooki on, the heart turns green (solid or blinking) when
  the cable is connected; with the Jooki off, it powers on by itself when the
  cable is connected. If neither happens, the charging path has a problem.

Their user guide adds that "a wet or contaminated USB-C connector may cause
excessive heat or melting", and that the charger should follow USB Battery
Charging 1.1 (an ordinary phone charger of 5 V).

**The port is only for charging.** On the Jooki 2 the USB data path is off from
the factory (`JOOKI_DISABLE_USB=1`, [01-notes.md](01-notes.md)); the kernel
switches the port between charger and headphone use (`usb_mux`), which is why
USB-C to jack cables and USB headphones are a separate story
([09-internals-deep-dive.md](09-internals-deep-dive.md) §1). One consequence
owners keep running into: **charging and wired headphones through the same
port do not mix**. When the cable goes in, the program only puts the
multiplexer on the charger side if headphones are *not* enabled
(`usb_mux`, in the original program and in `core/services/device.lua` alike),
which matches what owners see: with a splitter, the headphones work and the
charging does not (u/Rubman tried five). Muuselabs' own updater refuses to write
a firmware while the battery is low; OpenJooki asks you to keep the Jooki
plugged in for the same reason.

**A port that is coming loose** (a child's rough plugging is the usual cause):
it is soldered to the board, and replacing it with a plain soldering iron is
delicate. u/Open-Dig2504's advice: solder a charging lead directly to the
port's plus and minus pads and leave it permanently attached, with a plug
further up the lead
([r/jooki, June 2025](https://www.reddit.com/r/jooki/comments/1l404fr/usb_charging_port_replacement/)).
The other way out is a new-old-stock Jooki 2: a former distributor in Belgium
sells his remaining stock on eBay (u/polanri, r/jooki).

## 5. A Jooki that no longer lights up

**What a healthy start looks like.** Cable in or heart pressed: the heart
lights white at once, the ESP32 chip and Linux start from the memory card, the
start-up chime plays and the ring turns white (boot to ready measured at about
6.5 s on OpenJooki 2, about 9 s on 1.x, [21-architecture-2.0.md](21-architecture-2.0.md)),
and the side dots show the Wi-Fi state within the next ten seconds.

**Nothing at all, not even the heart.** The battery is flat or the charging
path is dead. Plug a 1 A charger for an hour: the Jooki must power on by itself
when the cable goes in (§4). If it never does, with another cable and charger,
the fault is the port, the cable or the cell (§3).

**The heart lights white (green on the charger), the side lights never come
on, no chime.** The controller is alive but Linux did not boot: this is the
most frequent "dead Jooki" on r/jooki, and every case that was opened and
reported back had the same cause, the **micro-SD card** inside, worn out (SD cards have a limited
number of writes, and the original system wrote its logs and several files a
second to it; [22-core-inventory.md](22-core-inventory.md) §7). A factory
reset from the buttons does nothing for it (owners report one side dot going
yellow, then nothing). u/Open-Dig2504 found bad sectors on the card and could
not even read it; a bit-for-bit copy of a healthy Jooki's card onto a new one
brought it back
([r/jooki, October 2024](https://www.reddit.com/r/jooki/comments/1gc4w5s/side_lights_wont_come_on_bad_sectors_on_internal/)).
Two things to know: a card sold as 8 GB can be smaller than the original
(7.95 GB) and then does not fit; take a bigger one, a *high endurance* model.
OpenJooki's [bigger SD card tool](sdcard.html) does that copy from a healthy
card (Windows, Mac, Linux) and grows the music partition; it needs a healthy
card to copy from. Community images exist (u/nv1t's recovery image, u/Rubman's
of September 2026); they contain their author's data.

**A new-old-stock Jooki on an early firmware** (the eBay stock): it asks for an
update it can no longer get, and USB headphones or Bluetooth may not work.
Owners fixed it by copying the card of an up-to-date Jooki onto it, which also
copies that Jooki's tokens and Spotify set-up (u/Rubman, r/jooki, 2025).
OpenJooki's release image is a whole system taken from a Jooki on the last
Muuselabs firmware (December 2022) with OpenJooki on top, so installing it does
the same without another Jooki. The
ESP32 chip's own firmware is a file on the card, written to the chip at boot
when the flag `/data/mode/ESP32_FIRMWARE_LOADED` is missing
([09-internals-deep-dive.md](09-internals-deep-dive.md)): removing that file
over SSH and restarting reprograms the chip from that file. It is the one
operation that can brick a Jooki if the power goes during it: plug it in first.

**"Restart it ten times."** Advice that goes round r/jooki, and it does
something real: the boot counter. U-Boot keeps `bootcount` in the HT chip's
memory, with `bootlimit=1`; a boot that reaches the running system resets it to
zero (`ht_reset_bootcount.sh`), a boot that is interrupted before that leaves
it incremented, and once it is over the limit U-Boot **boots the other system
partition** (`mender_altbootcmd`: slot 2 becomes 3 or the reverse). So cutting
the power a few times during boot makes the Jooki try its other copy of the
system. It helps when one copy is damaged (a botched update); it does nothing
for a dying card, and on a Jooki that boots fine it just switches to the older
copy, which OpenJooki's page then offers to update again. The factory copy
(partition 1, Muuselabs' original) is a third option, reached with
`factory_reset=1` in the U-Boot environment ([04-architecture.md](04-architecture.md)).

## 6. Sources

- Firmware read from our Jooki 2: `ht_ctrl` (strings: topics, charge states,
  colour names), `player.lib` (the light code, [22-core-inventory.md](22-core-inventory.md)),
  `ota2.sh`, `factory_reset.sh`, `power_overheat.sh`, the U-Boot environment.
- OpenJooki 2: `core/services/device.lua`, `core/kernel/config.lua`, unit specs
  `core/spec/device_spec.lua` (lights, battery thresholds, overheat).
- Muuselabs: the charging notice of May 2024 (r/jooki), the user guide
  (manuals.plus), the update script's colour table.
- r/jooki: the threads linked above, and u/nv1t's blog
  ([reviving-jooki](https://nv1t.github.io/blog/reviving-jooki/)) for the flags.
