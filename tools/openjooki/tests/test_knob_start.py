#!/usr/bin/env python3
"""The track knob's "back to the start" switch (#40), against the real core and the real buttons' tick.

Held to the left for 3 s: the first song of the playlist, and an audiobook forgets its saved place.
A short turn stays next / previous; with "both" halfway still winds; "wind" never restarts; with the volume all the way
down the same hold stays the parent-code gesture (10 s).
  python3 test_knob_start.py
"""
import time
import bench as B

R = B.Results(); check = R.check
spy = B.Spy("/j/audio/out/#")
j = B.boot()
SONGS = ["media/song1.mp3", "media/song2.mp3", "media/song3.mp3"]


def knob(side, down):
    j.c.publish("/j/gpio/input/" + side, "1" if down else "0")


def hold(side, seconds):
    knob(side, True); time.sleep(seconds); knob(side, False); j.barrier()


def pl_uri(pid, n):
    p = j.state["db"]["playlists"][pid]
    return j.state["db"]["tracks"][p["tracks"][n]]["filename"]


def now_index():
    return j.state["audio"]["nowPlaying"].get("trackIndex")


def play_at(pid, n):
    j.send("PLAYLIST_PLAY", {"playlistId": pid, "trackIndex": n})
    j.wait_state("audio.playback.state", "PLAYING")
    j.wait(lambda: now_index() == n, 5, "track %d" % n)
    time.sleep(0.3)


music = j.newpl("Songs", SONGS)
book = j.newpl("Book", SONGS, audiobook=True)
j.send("SET_VOL", {"vol": "40"}); j.barrier()

# --- its own switch (#40), off by default, then kept
check("off by default", j.state["audio"]["config"].get("knob_restart") is False, j.state["audio"]["config"])
j.send("SET_CFG", {"knob_restart": True})
j.wait_state("audio.config.knob_restart", True)
check("the switch is saved, the knob stays on songs", j.state["audio"]["config"].get("knob_mode", "song") == "song", j.state["audio"]["config"])

# --- held 3 s: back to the first song
play_at(music, 3)
n = spy.mark()
knob("prev", True); time.sleep(2.4)
check("not yet at 2.4 s", spy.payloads("/j/audio/out/play", n) == [], spy.since(n))
R.expect("at 3 s: the first song", lambda: now_index() == 1, 3, lambda: j.state["audio"]["nowPlaying"])
knob("prev", False); j.barrier(); time.sleep(0.3)
check("one single start, nothing more on release", len(spy.payloads("/j/audio/out/play", n)) == 1, spy.since(n))
check("it plays", j.state["audio"]["playback"]["state"] in ("PLAYING", "STARTING"), j.state["audio"]["playback"])

# --- a short turn stays the original Jooki's
play_at(music, 3)
hold("prev", 0.3)
R.expect("short turn left: previous song", lambda: now_index() == 2, 3, lambda: now_index())
hold("next", 0.3)
R.expect("short turn right: next song", lambda: now_index() == 3, 3, lambda: now_index())
play_at(music, 1)
n = spy.mark()
hold("next", 3.5)
R.expect("held to the right: only the next song", lambda: now_index() == 2, 3, lambda: now_index())
check("held to the right: one start", len(spy.payloads("/j/audio/out/play", n)) == 1, spy.since(n))

# --- an audiobook forgets its place
play_at(book, 2)
# A real seek, so the engine itself goes on from 90 s: a position published by hand was overwritten by
# the engine's next tick (~4 s into the chapter) when that tick came before the pause (red CI, 15-16/11).
# 91 s can only be a tick counted after the seek: every older report of the engine arrived before it.
j.send("SEEK", {"position_ms": 90000})
j.wait_state("audio.playback.position_ms", pred=lambda v: v and v >= 91000)
j.send("DO_PAUSE", {}); j.wait_state("audio.playback.state", "PAUSED")
j.send("DO_PLAY", {}); j.wait_state("audio.playback.state", "PLAYING")
R.expect("audiobook: its place was saved first", lambda: (j.state.get("bedtime") or {}).get("resume", {}).get(book, {}).get("pos", 0) > 5000, 3, lambda: j.state.get("bedtime"))
n = spy.mark()
hold("prev", 3.5)
R.expect("audiobook: chapter 1", lambda: now_index() == 1, 3, lambda: now_index())
time.sleep(0.5)
check("audiobook: no seek back to the old place", [p for p in spy.payloads("/j/audio/out/seek", n) if int(p.split("\t")[1]) > 5000] == [], spy.since(n))
R.expect("audiobook: the old place is gone", lambda: (j.state.get("bedtime") or {}).get("resume", {}).get(book, {}).get("pos", 0) < 5000, 3, lambda: j.state.get("bedtime"))

# --- volume all the way down: the same hold stays the parent-code gesture
j.send("SET_VOL", {"vol": "0"}); j.barrier()
play_at(music, 3)
n = spy.mark()
hold("prev", 3.5)
B.quiet(0.5, "the release")
check("volume at zero: no jump to the start", now_index() != 1, now_index())
j.send("SET_VOL", {"vol": "40"}); j.barrier()

# --- with 'both': halfway still winds, held left still goes back to the start
j.send("SET_CFG", {"knob_mode": "both"}); j.wait_state("audio.config.knob_mode", "both")
play_at(music, 2)
n = spy.mark()
hold("fwd", 1.3)   # wound once at 1 s
check("'both' + the switch: halfway winds", len(spy.payloads("/j/audio/out/skip_sec", n)) >= 1 and spy.payloads("/j/audio/out/play", n) == [], spy.since(n))
play_at(music, 3)
hold("prev", 3.5)
R.expect("'both' + the switch: held left, the first song", lambda: now_index() == 1, 3, lambda: now_index())

# --- switched off: the original Jooki
j.send("SET_CFG", {"knob_mode": "song", "knob_restart": False}); j.wait_state("audio.config.knob_restart", False)
play_at(music, 3)
hold("prev", 3.5)
R.expect("as the original Jooki: previous song on release", lambda: now_index() == 2, 3, lambda: now_index())
j.send("SET_CFG", {"knob_restart": True}); j.wait_state("audio.config.knob_restart", True)
j.send("SET_CFG", {"knob_mode": "wind"}); j.wait_state("audio.config.knob_mode", "wind")
play_at(music, 2)
n = spy.mark()
hold("prev", 3.5)
check("'wind', even with the switch on: it winds, never restarts", spy.payloads("/j/audio/out/play", n) == [] and len(spy.payloads("/j/audio/out/skip_sec", n)) >= 1, spy.since(n))
j.send("SET_CFG", {"knob_mode": "song"}); j.barrier()

# --- nothing loaded: nothing happens
j.close()
j = B.boot()
# 2.5.1-2.5.3's "start" (an older page) is read as songs + the switch
j.send("SET_CFG", {"knob_mode": "start"}); j.wait_state("audio.config.knob_restart", True)
check("the old 'start' becomes songs + the switch", j.state["audio"]["config"]["knob_mode"] == "song", j.state["audio"]["config"])
n = spy.mark()
hold("prev", 3.5)
check("nothing loaded: no sound", spy.payloads("/j/audio/out/play", n) == [], spy.since(n))
j.close()
R.finish()
