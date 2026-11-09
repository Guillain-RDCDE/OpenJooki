#!/usr/bin/env python3
"""Home Assistant connecting while music plays (#28), against the real core.

ha-jooki sends CONNECT then GET_STATE each time it connects. CONNECT plays the "connect" sound, and
audio_ctrl has one pipeline: the sound replaced the song, then every "resume" played the sound again.
Here the core must leave a loaded song alone, and a sound that does interrupt one (a warning) must
bring the song back with its own "play 7" and a seek, never with "cont".
  python3 test_ha_connect.py
"""
import json
import bench as B

MUSIC, SOUND = 7, 3
FOX = "04000000F00001"
R = B.Results(); check = R.check
spy = B.Spy("/j/audio/out/#")


def pre():
    json.dump({"_": {"version": 1},
               "Evt.Mobile.connect": {"filename": "connect.ogg"},
               "Evt.Character.Write": {"filename": "write.ogg"}},
              open("/jooki/app/system/tracks.json", "w"))


def ha_connects(j):
    """What ha-jooki's mqtt_client publishes on connect."""
    j.c.publish("/j/web/input/CONNECT", json.dumps({"jooki": {"live": "10.0.0.2", "version": "ha-jooki", "label": "10.0.0.2"}}))
    j.c.publish("/j/web/input/GET_STATE", "{}")
    j.barrier()


def sound_ended(j):
    j.c.publish("/j/audio/input/ended", json.dumps({"id": SOUND}))


j = B.boot(pre=pre)
pl = j.newpl("Songs", ["media/song1.mp3", "media/song2.mp3"], star=None)
j.send("PLAYLIST_PLAY", {"playlistId": pl, "trackIndex": 0})
j.wait_state("audio.playback.state", "PLAYING")
uri = j.state["audio"]["nowPlaying"]["uri"]

# --- 1. Home Assistant connects while a song plays
n = spy.mark()
ha_connects(j)
sent = spy.since(n, "/j/audio/out/")
check("connecting sends nothing to the engine while a song plays", sent == [], sent)
check("the song still plays", j.state["audio"]["playback"]["state"] == "PLAYING", j.state["audio"]["playback"])

# --- 2. ... and while a song is paused: the sound must not take its place either
j.send("DO_PAUSE", {})
j.wait_state("audio.playback.state", "PAUSED")
n = spy.mark()
ha_connects(j)
check("connecting sends nothing to the engine while a song is paused", spy.since(n, "/j/audio/out/") == [])
n = spy.mark()
j.send("DO_PLAY", {})
j.wait_state("audio.playback.state", "PLAYING")
check("Play continues the paused song", spy.payloads("/j/audio/out/cont", n) == [str(MUSIC)], spy.since(n))

# --- 3. A sound that does pause the music: the song comes back itself, at its place
j.c.publish("/j/audio/input/position", json.dumps({"id": MUSIC, "pos": 42000}))
j.wait_state("audio.playback.position_ms", 42000)
n = spy.mark()
j.c.publish("/j/event", "Evt.Character.Write")
R.expect("the sound takes the engine", lambda: any(p.startswith("3\t") for p in spy.payloads("/j/audio/out/play", n)))
check("the music is paused first", spy.payloads("/j/audio/out/pauz", n) == [str(MUSIC)], spy.since(n))
B.quiet(0.3, "the engine reports the pause and the sound")
n = spy.mark()
sound_ended(j)
want = "%d\t%s" % (MUSIC, uri)
R.expect("after the sound, the same song is loaded again", lambda: want in spy.payloads("/j/audio/out/play", n))
check("never 'cont': on one pipeline it would play the sound again", spy.payloads("/j/audio/out/cont", n) == [], spy.since(n))
R.expect("and goes back to its place", lambda: "%d\t42000" % MUSIC in spy.payloads("/j/audio/out/seek", n))
j.wait_state("audio.playback.state", "PLAYING")

# --- 4. With nothing loaded the connect sound still greets, as the original did
n = spy.mark()
j.send("DO_PAUSE", {})
j.wait_state("audio.playback.state", "PAUSED")
j.c.publish("/j/audio/input/stopped", json.dumps({"id": MUSIC}))
j.wait_state("audio.playback.state", "STOPPED")
n = spy.mark()
ha_connects(j)
R.expect("idle: the connect sound plays", lambda: any(p.startswith("3\t") for p in spy.payloads("/j/audio/out/play", n)))
sound_ended(j)

j.close()
R.finish()
