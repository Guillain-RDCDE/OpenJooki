"""Bedtime tests on the bench: the real Jooki program (patched) + mosquitto + fake audio.
Checks resume, sleep timer, night window, volume limit and lights end to end.  python3 test_bedtime.py"""
import datetime, json, os
import bench as B
DB = B.DB
FOX = "04000000F00001"            # fox token (star 257 = 0x101)
MUSIC = 7                         # id the program gives to music playback (system sounds use 3)
R = B.Results(); check = R.check

# everything the program sends to the hardware side
spy = B.Spy("/j/audio/out/#", "/j/led/output/#")
def sent(topic, n): return spy.payloads(topic, n)

def vols(): return [int(x) for x in open(B.VOL_LOG).read().split()] if os.path.exists(B.VOL_LOG) else []
def start(pre=None): return B.boot(pre=pre)         # a fresh Jooki, the volume log emptied
def restart(j): return B.restart(j)
def bt(j): return j.bt
def utc_min(): n = datetime.datetime.now(datetime.timezone.utc); return n.hour * 60 + n.minute
def hhmm(m): m %= 1440; return "%02d:%02d" % (m // 60, m % 60)
NIGHT = lambda: {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hhmm(utc_min() - 60), "stop": hhmm(utc_min() + 60)}
DAY = lambda: {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hhmm(utc_min() + 120), "stop": hhmm(utc_min() + 180)}
def newpl(j, title, files, audiobook=False, star=None):
    return j.newpl(title, ["media/%s.mp3" % f for f in files], audiobook=audiobook, star=star)
def ended(j): j.c.publish("/j/audio/input/ended", json.dumps({"id": MUSIC}))

# ---------- settings
j = start()
b = bt(j)
check("B1 defaults: 20:00-07:00, 20 min, 30 %, dimmed lights, Paris time",
      b.get("cfg") == {"enabled": True, "start": 1200, "stop": 420, "timer": 20, "maxvol": 30, "dim": True, "tzbase": 60, "tzdst": "EU"}, b)
j.errors.clear(); j.send("OJ_BEDTIME_SET", {"start": "24:10"})
R.expect("B2 invalid setting refused with a message", lambda: j.errors and "invalid start" in str(j.errors[-1]) and bt(j)["cfg"]["start"] == 1200, 5, lambda: j.errors)
j.send("OJ_BEDTIME_SET", {"start": "20:30", "stop": "06:45", "timer": 25, "maxvol": 35})
cfg = lambda: bt(j)["cfg"]
R.expect("B2 settings changed", lambda: (cfg()["start"], cfg()["stop"], cfg()["timer"], cfg()["maxvol"]) == (1230, 405, 25, 35), 5, cfg)
j = restart(j)
check("B2 settings survive a restart", bt(j)["cfg"]["start"] == 1230 and bt(j)["cfg"]["maxvol"] == 35, bt(j))

# ---------- night window: volume limit, lights, automatic timer
q = newpl(j, "Musique", ["song1", "song2", "song3"], star="Jooki.Fox")
j.send("OJ_BEDTIME_SET", dict(NIGHT(), maxvol=30, timer=1))
R.expect("B3 night detected", lambda: bt(j).get("night") is True, 5, lambda: bt(j))
j.send("SET_VOL", {"vol": 90})
R.expect("B3 night: volume 90 asked, 30 sent to the speaker", lambda: vols()[-1] == 30 and j.get("audio.config.volume") == 90, 5, lambda: (vols()[-5:], j.get("audio.config")))
n = spy.mark(); j.nfc(FOX, "101")
def rings(): return [p for p in sent("/j/led/output/set_raw", n) if p.startswith("RING") or p.startswith("PREV")]
B.poll(lambda: j.get("bedtime.sleep.auto") and rings(), 5)     # the token plays: lights set, the automatic timer on
check("B4 night: lights dimmed", rings() and all(max(int(x) for x in p.split(",")[1:4]) <= 10 for p in rings()), rings())
sl = bt(j).get("sleep") or {}
check("B5 night: playback gets the automatic timer", sl.get("auto") is True and sl.get("total") == 60 and sl.get("mode") == "time", sl)
j.nfc_off(); j.wait_state("audio.playback.state", "PAUSED")
j.send("OJ_BEDTIME_SET", DAY())
R.expect("B3 day: back to the knob volume", lambda: bt(j).get("night") is False and vols()[-1] == 90, 5, lambda: (bt(j).get("night"), vols()[-3:]))
j.send("OJ_SLEEP", {"cancel": True}); j.wait(lambda: not bt(j).get("sleep"), what="sleep timer cancelled")

# ---------- sleep timer: fade then pause, volume back
j.send("PLAYLIST_PLAY", {"playlistId": q}); j.wait_state("audio.playback.state", "PLAYING")
n0 = len(vols()); j.send("OJ_SLEEP", {"seconds": 6})
R.expect("B6 timer shown to the page", lambda: (bt(j).get("sleep") or {}).get("remaining") in (5, 6), 5, lambda: bt(j).get("sleep"))
j.wait_state("audio.playback.state", "PAUSED", 10)
B.poll(lambda: vols()[-1] == 90 and not bt(j).get("sleep"), 5)      # the volume put back and the timer gone follow the pause
v = vols()[n0:]
check("B6 volume lowered gradually before the pause", len([x for x in v if 0 < x < 90]) >= 2 and min(v) <= 30, v)
check("B6 paused at the end, timer gone", j.pb == "PAUSED" and not bt(j).get("sleep"), j.get("audio.playback"))
check("B6 volume back to normal after the pause", vols()[-1] == 90, vols()[-3:])

# ---------- end of chapter
j.send("PLAYLIST_PLAY", {"playlistId": q, "trackIndex": 1}); j.wait(lambda: j.np.get("trackIndex") == 1 and j.pb == "PLAYING", what="track 1 playing")
ended(j)
R.expect("B7 without timer: next track", lambda: j.np.get("trackIndex") == 2, 5, lambda: j.np)
j.send("OJ_SLEEP", {"mode": "track"})
R.expect("B7 'end of this chapter' shown", lambda: (bt(j).get("sleep") or {}).get("mode") == "track", 5, lambda: bt(j).get("sleep"))
ended(j)
R.expect("B7 end of chapter: stops instead of the next track", lambda: j.np.get("trackIndex") == 2 and j.pb == "ENDED" and not bt(j).get("sleep"), 5,
         lambda: (j.np.get("trackIndex"), j.get("audio.playback")))
j.close()

# ---------- audiobook: chapter + position survive a restart
j = start()
bk = newpl(j, "Le Petit Prince", ["song1", "song2", "song3"], audiobook=True, star="Jooki.Fox")
j.send("PLAYLIST_PLAY", {"playlistId": bk, "trackIndex": 2}); j.wait(lambda: j.np.get("trackIndex") == 2 and j.pb == "PLAYING", what="chapter 2 playing")
j.send("SEEK", {"position_ms": 40000}); j.wait(lambda: j.get("audio.playback.position_ms", 0) >= 40000, what="position past 40 s")
j.nfc(FOX, "101"); j.wait(lambda: j.nfc_state.get("starId") == "Jooki.Fox")
j.nfc_off(); j.wait_state("audio.playback.state", "PAUSED")   # token lifted = pause
def resume_file(): return json.load(open(DB + "/resume.json")) if os.path.exists(DB + "/resume.json") else {}
B.poll(lambda: resume_file().get(bk, {}).get("pos", 0) >= 40000, 5)
res = resume_file()
tr = j.pls[bk]["tracks"]
check("B8 position saved when paused", res.get(bk, {}).get("id") == tr[1] and res[bk]["pos"] >= 40000, res)
R.expect("B8 resume shown to the page", lambda: (bt(j).get("resume") or {}).get(bk, {}).get("id") == tr[1], 5, lambda: bt(j).get("resume"))
j = restart(j)
n = spy.mark(); j.nfc(FOX, "101")
B.poll(lambda: j.np.get("playlistId") == bk and sent("/j/audio/out/seek", n), 5)
np = j.np
seeks = [int(p.split("\t")[1]) for p in sent("/j/audio/out/seek", n)]
check("B9 after a restart: same chapter", np.get("playlistId") == bk and np.get("trackIndex") == 2, np)
check("B9 after a restart: 15 s before the saved position", seeks and 25000 <= seeks[0] <= 29000, seeks)
j.nfc_off(); j.wait_state("audio.playback.state", "PAUSED")
j.send("OJ_RESUME_RESET", {"playlistId": bk}); j.poll(lambda: bk not in (bt(j).get("resume") or {}), 5)
check("B10 'start again from the beginning'", bk not in (bt(j).get("resume") or {}) and bk not in resume_file(), bt(j).get("resume"))
n = spy.mark(); j.nfc(FOX, "101")
B.poll(lambda: j.np.get("trackIndex") == 1 and j.pb == "PLAYING", 5)
B.quiet(0.3, "a resume seek, had there been one, goes out with the play command")
check("B10 then plays chapter 1 from the start", j.np.get("trackIndex") == 1 and not sent("/j/audio/out/seek", n), j.np)
j.nfc_off(); j.wait_state("audio.playback.state", "PAUSED")
j.send("PLAYLIST_PLAY", {"playlistId": bk, "trackIndex": 3}); j.wait(lambda: j.np.get("trackIndex") == 3 and j.pb == "PLAYING", what="chapter 3 playing")
ended(j)
R.expect("B11 end of the book: next time starts at chapter 1", lambda: bk not in (bt(j).get("resume") or {}), 5, lambda: bt(j).get("resume"))
j.close()
B.check_clean_log(R, "B12 no error in the bedtime code")
spy.close()
R.finish()
