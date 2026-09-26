# Bedtime: audiobook resume, sleep timer, night mode

Since firmware 1.3.0 the Jooki helps at bedtime, without a phone in the room.

## What it does

**Audiobooks resume where the child fell asleep.** For a playlist marked
*Audiobook*, the Jooki remembers the chapter **and** the position in it, on its
own storage (`/jooki/external/jooki/resume.json`). This survives the Jooki
turning itself off (it does after 15 minutes of silence on battery). It starts
again a little earlier so the child gets back into the story:

| How it stopped | Next start |
|---|---|
| Token lifted and put back within a minute | exactly where it was |
| Paused for more than a minute, or the Jooki was turned off | 15 s earlier |
| Stopped by the sleep timer | 60 s earlier (the minute when the volume was going down) |
| End of a chapter | beginning of the next chapter |
| End of the book | chapter 1 |

The playlist page shows *"Will resume at chapter 12 · 3:25"* and a button
*Start again from the beginning*. Before 1.3.0 the Jooki only remembered the
chapter, in memory: after turning itself off, a book always started over.

**Sleep timer.** From the player on the page: 10, 20, 30, 45 or 60 minutes, or
*End of chapter*. The volume goes down gently during the last minute (the last
20 seconds of the chapter in *End of chapter* mode), then the Jooki pauses and
its volume goes back to normal for the next time. The player bar shows a moon and
the time left.

**Night mode** (Settings → Bedtime). During a time window (default 20:00–07:00):

- every playback started with a token gets the sleep timer on its own
  (default 20 minutes, *None* to disable);
- the volume is limited (default 30 %), **whatever the position of the knob**;
- the lights are dimmed (about 5 % of their normal brightness).

The Jooki keeps UTC time from the Internet (ntpd). The page tells it the
family's time zone the first time it is opened; for Europe the summer-time rule
(last Sunday of March / October) is applied on the Jooki itself, so the window
stays right all year. If the clock is not set (no Internet since boot), night
mode stays off.

**Put back in order.** Uploads arrive in the order they finish, not in the order
of the files. When a playlist is not in title order, its page offers *Put back in
order (1, 2, 3…)* (natural order: 2 before 10).

## How it is built

One small Lua module (`ojbed`, in `tools/openjooki/lua_patches.py`) plus a few
hooks in the Jooki program, applied like the other fixes (A/B, rollback armed).

- **Volume**: the knob sends its position every second and the program applies
  it at once, so a limit or a fade set anywhere else would be overwritten. They
  are applied where the volume reaches the hardware (`c_alsa_set_volume`); the
  volume the knob asked for is kept unchanged and comes back as soon as the limit
  or the fade ends.
- **Clock**: the main loop (every 0.5 s) checks the night window every 15 s,
  drives the fade and saves the resume position at most once a minute while
  playing (and at every pause, stop, end of chapter and power-off).
- **Files**: `bedtime.json` (settings) and `resume.json` (positions), written with
  the program's own safe method (temporary file, `.bak`, rename).

Messages from the page (`/j/web/input/...`), all answered in the state under
`bedtime` (`cfg`, `night`, `sleep`, `resume`):

| Message | Payload |
|---|---|
| `OJ_SLEEP` | `{"minutes": 20}` · `{"mode": "track"}` · `{"cancel": true}` |
| `OJ_BEDTIME_SET` | any of `enabled`, `start`/`stop` (`"20:00"`), `timer` (0–180 min), `maxvol` (5–100), `dim`, `tzbase` (minutes), `tzdst` (`"EU"`/`"none"`) |
| `OJ_RESUME_RESET` | `{"playlistId": "..."}` |

Invalid values are refused with a message on `/j/web/output/error`; nothing is
changed.

## Tests

- `tests/unit_bedtime.py`: the module alone under Lua 5.1 with a fake clock
  (summer-time changes, night window, fade, timer, resume, lights): 57 checks.
- `tests/test_bedtime.py`: the real program on the bench (volume sent to the
  hardware, lights, timer, end of chapter, resume across a restart): 24 checks.
- `tests/e2e.py`: the page (settings, timer, countdown, resume, sorting): 41 checks.
- On a real Jooki v2: resume after pause and after a long pause, dimmed lights,
  timer pausing the real player, settings saved.
