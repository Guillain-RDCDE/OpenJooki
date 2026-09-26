"""Bedtime tests on the bench: the real Jooki program (patched) + mosquitto + fake audio.
Checks resume, sleep timer, night window, volume limit and lights end to end.  python3 test_bedtime.py"""
import datetime, json, os, subprocess, sys, threading, time
import paho.mqtt.client as mqtt
from jk import Jooki
LUA = os.environ.get("PLAYER_LUA", "player.patched.lua")
DB = "/jooki/external/jooki"
FOX = "04000000F00001"            # fox token (star 257 = 0x101)
MUSIC = 7                         # id the program gives to music playback (system sounds use 3)
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))

# everything the program sends to the hardware side
bus = []
spy = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "spy")
spy.on_message = lambda c, u, m: bus.append((time.time(), m.topic, m.payload.decode(errors="replace")))
spy.connect("127.0.0.1", 1883); spy.subscribe("/j/audio/out/#"); spy.subscribe("/j/led/output/#"); spy.loop_start()
def sent(topic, since): return [p for t, tp, p in bus if tp == topic and t >= since]

def vols(): return [int(x) for x in open("/tmp/bench_vol.log").read().split()] if os.path.exists("/tmp/bench_vol.log") else []
def start(pre=None):
    subprocess.run(["bash", "setup.sh"], capture_output=True)
    if pre: pre()
    open("/tmp/bench_vol.log", "w").close()
    subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
    return Jooki()
def restart():
    subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
    return Jooki()
def bt(j): return j.state.get("bedtime", {})
def utc_min(): n = datetime.datetime.now(datetime.timezone.utc); return n.hour * 60 + n.minute
def hhmm(m): m %= 1440; return "%02d:%02d" % (m // 60, m % 60)
NIGHT = lambda: {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hhmm(utc_min() - 60), "stop": hhmm(utc_min() + 60)}
DAY = lambda: {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hhmm(utc_min() + 120), "stop": hhmm(utc_min() + 180)}
def newpl(j, title, files, audiobook=False, star=None):
    before = set(j.pls); j.send("PLAYLIST_NEW", {"title": title}); j.wait(lambda: len(set(j.pls) - before) == 1)
    p = (set(j.pls) - before).pop()
    for f in files: j.upload("media/%s.mp3" % f, p); j.settle(1.2)
    upd = {"id": p, "audiobook": audiobook}
    if star: upd["star"] = star
    j.send("PLAYLIST_UPDATE", {"playlist": upd}); j.settle()
    return p

# ---------- settings
j = start()
b = bt(j)
check("B1 defaults: 20:00-07:00, 20 min, 30 %, dimmed lights, Paris time",
      b.get("cfg") == {"enabled": True, "start": 1200, "stop": 420, "timer": 20, "maxvol": 30, "dim": True, "tzbase": 60, "tzdst": "EU"}, b)
j.errors.clear(); j.send("OJ_BEDTIME_SET", {"start": "24:10"}); j.settle()
check("B2 invalid setting refused with a message", j.errors and "invalid start" in str(j.errors[-1]) and bt(j)["cfg"]["start"] == 1200, j.errors)
j.send("OJ_BEDTIME_SET", {"start": "20:30", "stop": "06:45", "timer": 25, "maxvol": 35}); j.settle()
c = bt(j)["cfg"]
check("B2 settings changed", (c["start"], c["stop"], c["timer"], c["maxvol"]) == (1230, 405, 25, 35), c)
j.close(); j = restart()
check("B2 settings survive a restart", bt(j)["cfg"]["start"] == 1230 and bt(j)["cfg"]["maxvol"] == 35, bt(j))

# ---------- night window: volume limit, lights, automatic timer
q = newpl(j, "Musique", ["song1", "song2", "song3"], star="Jooki.Fox")
j.send("OJ_BEDTIME_SET", dict(NIGHT(), maxvol=30, timer=1)); j.settle()
check("B3 night detected", bt(j).get("night") is True, bt(j))
j.send("SET_VOL", {"vol": 90}); j.settle()
check("B3 night: volume 90 asked, 30 sent to the speaker", vols()[-1] == 30 and j.state["audio"]["config"]["volume"] == 90, (vols()[-5:], j.state["audio"]["config"]))
t0 = time.time(); j.nfc(FOX, "101"); j.settle(1.5)
rings = [p for p in sent("/j/led/output/set_raw", t0) if p.startswith("RING") or p.startswith("PREV")]
check("B4 night: lights dimmed", rings and all(max(int(x) for x in p.split(",")[1:4]) <= 10 for p in rings), rings)
sl = bt(j).get("sleep") or {}
check("B5 night: playback gets the automatic timer", sl.get("auto") is True and sl.get("total") == 60 and sl.get("mode") == "time", sl)
j.nfc_off(); j.settle()
j.send("OJ_BEDTIME_SET", DAY()); j.settle()
check("B3 day: back to the knob volume", bt(j).get("night") is False and vols()[-1] == 90, (bt(j).get("night"), vols()[-3:]))
j.send("OJ_SLEEP", {"cancel": True}); j.settle()

# ---------- sleep timer: fade then pause, volume back
j.send("PLAYLIST_PLAY", {"playlistId": q}); j.wait(lambda: j.state["audio"]["playback"].get("state") == "PLAYING")
n0 = len(vols()); j.send("OJ_SLEEP", {"seconds": 6}); j.settle()
check("B6 timer shown to the page", (bt(j).get("sleep") or {}).get("remaining") in (5, 6), bt(j).get("sleep"))
j.wait(lambda: j.state["audio"]["playback"].get("state") == "PAUSED", 10); time.sleep(1)
v = vols()[n0:]
check("B6 volume lowered gradually before the pause", len([x for x in v if 0 < x < 90]) >= 2 and min(v) <= 30, v)
check("B6 paused at the end, timer gone", j.state["audio"]["playback"].get("state") == "PAUSED" and not bt(j).get("sleep"), j.state["audio"]["playback"])
check("B6 volume back to normal after the pause", vols()[-1] == 90, vols()[-3:])

# ---------- end of chapter
j.send("PLAYLIST_PLAY", {"playlistId": q, "trackIndex": 1}); j.wait(lambda: j.state["audio"]["playback"].get("state") == "PLAYING"); j.settle()
j.c.publish("/j/audio/input/ended", json.dumps({"id": MUSIC})); j.settle(1.5)
check("B7 without timer: next track", j.state["audio"]["nowPlaying"].get("trackIndex") == 2, j.state["audio"]["nowPlaying"])
j.send("OJ_SLEEP", {"mode": "track"}); j.settle()
check("B7 'end of this chapter' shown", (bt(j).get("sleep") or {}).get("mode") == "track", bt(j).get("sleep"))
j.c.publish("/j/audio/input/ended", json.dumps({"id": MUSIC})); j.settle(1.5)
check("B7 end of chapter: stops instead of the next track", j.state["audio"]["nowPlaying"].get("trackIndex") == 2 and j.state["audio"]["playback"].get("state") == "ENDED" and not bt(j).get("sleep"),
      (j.state["audio"]["nowPlaying"].get("trackIndex"), j.state["audio"]["playback"]))
j.close()

# ---------- audiobook: chapter + position survive a restart
j = start()
bk = newpl(j, "Le Petit Prince", ["song1", "song2", "song3"], audiobook=True, star="Jooki.Fox")
j.send("PLAYLIST_PLAY", {"playlistId": bk, "trackIndex": 2}); j.wait(lambda: j.state["audio"]["playback"].get("state") == "PLAYING"); j.settle()
j.send("SEEK", {"position_ms": 40000}); j.settle(2.5)
j.nfc(FOX, "101"); j.settle(); j.nfc_off(); j.settle()   # token lifted = pause
res = json.load(open(DB + "/resume.json")) if os.path.exists(DB + "/resume.json") else {}
tr = j.pls[bk]["tracks"]
check("B8 position saved when paused", res.get(bk, {}).get("id") == tr[1] and res[bk]["pos"] >= 40000, res)
check("B8 resume shown to the page", (bt(j).get("resume") or {}).get(bk, {}).get("id") == tr[1], bt(j).get("resume"))
j.close(); j = restart()
t0 = time.time(); j.nfc(FOX, "101"); j.settle(2)
np = j.state["audio"]["nowPlaying"]
seeks = [int(p.split("\t")[1]) for p in sent("/j/audio/out/seek", t0)]
check("B9 after a restart: same chapter", np.get("playlistId") == bk and np.get("trackIndex") == 2, np)
check("B9 after a restart: 15 s before the saved position", seeks and 25000 <= seeks[0] <= 29000, seeks)
j.nfc_off(); j.settle()
j.send("OJ_RESUME_RESET", {"playlistId": bk}); j.settle()
check("B10 'start again from the beginning'", bk not in (bt(j).get("resume") or {}) and bk not in json.load(open(DB + "/resume.json")), bt(j).get("resume"))
t0 = time.time(); j.nfc(FOX, "101"); j.settle(1.5)
check("B10 then plays chapter 1 from the start", j.state["audio"]["nowPlaying"].get("trackIndex") == 1 and not sent("/j/audio/out/seek", t0), j.state["audio"]["nowPlaying"])
j.nfc_off(); j.settle()
j.send("PLAYLIST_PLAY", {"playlistId": bk, "trackIndex": 3}); j.wait(lambda: j.state["audio"]["nowPlaying"].get("trackIndex") == 3); j.settle()
j.c.publish("/j/audio/input/ended", json.dumps({"id": MUSIC})); j.settle(1.5)
check("B11 end of the book: next time starts at chapter 1", bk not in (bt(j).get("resume") or {}), bt(j).get("resume"))
j.close()
log = open("/tmp/player.log").read()
check("B12 no error in the bedtime code", log.count("OJ_TICK") == 0 and log.count("ERR_HANDLER") == 0, [l for l in log.splitlines() if "OJ_TICK" in l or "ERR_HANDLER" in l][:3])
spy.loop_stop()
bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
