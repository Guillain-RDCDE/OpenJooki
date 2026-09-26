"""Backend regression tests: real Jooki Lua app (patched) + mosquitto on the bench."""
import json, os, subprocess, time, sys, shutil
from jk import Jooki
LUA = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PLAYER_LUA", "player.patched.lua")
DB = "/jooki/external/jooki"
BD1, BD2 = "04000000B00001", "04000000B00003"   # two black dragons (star 262 = 0x106)
FOX = "04000000F00001"                          # fox (257 = 0x101)
results = []
def check(name, cond, info=""):
    results.append((name, bool(cond))); print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  -> %s" % (info,)))
def fresh(pre=None):
    subprocess.run(["bash", "setup.sh"], capture_output=True)
    if pre: pre()
    open("/tmp/bench_services.log", "w").close()
    subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1.0)
    return Jooki()
def pid_player():
    # the 1.x program runs as "lua5.1 run.lua ...", the 2.0 core as "lua5.1 .../harness.lua ..."
    return subprocess.run(["pgrep", "-f", "^lua5.1 (run|.*harness)"], capture_output=True, text=True).stdout.strip()
def beeps(): return open("/tmp/bench_services.log").read().count("errorbeep")
def newpl(j, title):
    before = set(j.pls); j.send("PLAYLIST_NEW", {"title": title, "audiobook": False})
    j.wait(lambda: len(set(j.pls) - before) == 1); return (set(j.pls) - before).pop()
def disk(tid): return os.path.exists("%s/uploads/%s" % (DB, tid))
def trash(j): return j.pls.get("TRASH", {}).get("tracks", [])

# ---------- tokens
j = fresh(); p = newpl(j, "Comptines")
j.nfc(BD1, "106"); j.nfc_off(); j.settle()
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "star": "Jooki.Black.Dragon"}}); j.settle()
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "  Dark  "}); j.settle()
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "Dark"}); j.settle()
check("T1 rename twice: no error", j.errors == [], j.errors)
check("T1 name trimmed and saved", j.tokens[BD1].get("name") == "Dark", j.tokens[BD1])
check("T2 naming keeps character link", j.pls[p].get("star") == "Jooki.Black.Dragon" and not j.pls[p].get("tagId"), j.pls[p])
j.upload("media/song1.mp3", p); j.settle(1.5)
j.nfc(BD2, "106"); j.settle()
check("T2 another black dragon plays it", j.state["audio"]["nowPlaying"].get("playlistId") == p, j.state["audio"].get("nowPlaying"))
j.nfc_off(); j.settle()
p2 = newpl(j, "Autre")
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p2, "tagId": BD1}}); j.settle()
check("T3 old per-token link converted to character link (and unique)",
      j.pls[p2].get("star") == "Jooki.Black.Dragon" and not j.pls[p2].get("tagId") and not j.pls[p].get("star"), (j.pls[p], j.pls[p2]))
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p2, "star": False}}); j.settle()
check("T5 unlink playlist", not j.pls[p2].get("star") and not j.pls[p2].get("tagId"), j.pls[p2])
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "star": "Jooki.Black.Dragon"}}); j.settle()
j.send("TOKEN_DELETE", {"tagId": BD1}); j.settle()
check("T6 forgetting a token keeps the playlist link", j.pls[p].get("star") == "Jooki.Black.Dragon" and BD1 not in j.tokens, (j.pls[p], j.tokens))
j.send("TOKEN_EDIT", {"tagId": BD2, "name": "X"}); j.send("TOKEN_EDIT", {"tagId": BD2, "name": ""}); j.settle()
check("T1b clearing a name", "name" not in j.tokens[BD2], j.tokens[BD2])
check("T1c no errors so far", j.errors == [], j.errors)
j.close()

# ---------- migration at boot + image preserved
def pre_mig():
    json.dump({"_": {"version": 1}, "user_1": {"title": "Old", "tagId": BD1, "tracks": []},
               "user_2": {"title": "Fox", "star": "Jooki.Fox", "tracks": []},
               "user_3": {"title": "FoxTag", "tagId": FOX, "tracks": []}}, open(DB + "/playlists.json", "w"))
    json.dump({"_": {"version": 1}, BD1: {"name": "Dark", "starId": "Jooki.Black.Dragon", "seen": 3, "image": "custom.png"},
               FOX: {"starId": "Jooki.Fox", "seen": 1}}, open(DB + "/tokens.json", "w"))
j = fresh(pre_mig)
check("T4 migration tagId -> star", j.pls["user_1"].get("star") == "Jooki.Black.Dragon" and not j.pls["user_1"].get("tagId"), j.pls["user_1"])
check("T4 migration keeps existing star owner", j.pls["user_2"].get("star") == "Jooki.Fox" and not j.pls["user_3"].get("star") and not j.pls["user_3"].get("tagId"), (j.pls["user_2"], j.pls["user_3"]))
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "Dark2"}); j.settle()
check("T1d image preserved on rename", j.tokens[BD1].get("image") == "custom.png", j.tokens[BD1])
j.close()

# ---------- TRASH and data safety
j = fresh(); p = newpl(j, "P")
j.upload("media/song1.mp3"); j.settle(1.5)
t1 = [k for k in j.tracks][0]
check("T7 upload without playlist appears in Unused tracks at once", trash(j) == [t1], j.pls)
for payload in ({"id": "TRASH", "title": "Test"}, {"id": "TRASH", "star": "Jooki.Dragon"}):
    j.errors.clear(); j.send("PLAYLIST_UPDATE", {"playlist": payload}); j.settle()
    check("T7 TRASH refuses %s" % list(payload)[1], j.errors and j.errors[-1]["msg"] == "TRASH_READONLY" and j.pls["TRASH"].get("title") == "Unused tracks" and not j.pls["TRASH"].get("star"), (j.errors, j.pls["TRASH"]))
j.errors.clear(); j.send("PLAYLIST_DELETE", {"playlistId": "TRASH"}); j.settle()
check("T7 TRASH cannot be deleted", "TRASH" in j.pls and j.errors, j.errors)
j.errors.clear(); j.send("PLAYLIST_ADD_TRACK", {"playlistId": "TRASH", "trackId": t1}); j.settle()
check("T7 nothing can be added to TRASH", j.errors and trash(j) == [t1], (j.errors, trash(j)))
j.send("PLAYLIST_ADD_TRACK", {"playlistId": p, "trackId": t1}); j.settle()
check("T8 used track leaves Unused tracks immediately", "TRASH" not in j.pls and j.pls[p]["tracks"] == [t1], j.pls)
j.upload("media/song2.mp3"); j.settle(1.5)
t2 = [k for k in j.tracks if k != t1][0]
# stale client: asks TRASH to keep nothing, while t1 is used by P
j.send("PLAYLIST_UPDATE", {"playlist": {"id": "TRASH", "tracks": []}}); j.settle(1)
check("T8 emptying Unused tracks deletes only unused files", disk(t1) and t1 in j.tracks and not disk(t2) and t2 not in j.tracks, (disk(t1), disk(t2)))
j.upload("media/song3.mp3", p); j.settle(1.5)
t3 = [k for k in j.pls[p]["tracks"] if k != t1][0]
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "tracks": [t3]}}); j.settle()
check("T9 track removed from a playlist goes to Unused tracks (file kept)", trash(j) == [t1] and disk(t1), (trash(j), disk(t1)))
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "tracks": [t3, "deadbeefdeadbeef"]}}); j.settle()
check("T9b unknown track ids ignored", j.pls[p]["tracks"] == [t3], j.pls[p])
j.send("PLAYLIST_DELETE", {"playlistId": p}); j.settle()
check("T10 deleting a playlist sends its tracks to Unused tracks", sorted(trash(j)) == sorted([t1, t3]) and disk(t3), trash(j))
# duplicate upload to a missing playlist must not delete the existing file
j.errors.clear(); j.upload("media/song1.mp3", "user_doesnotexist"); j.settle(1.5)
check("T11 failed duplicate upload keeps the existing file", disk(t1) and t1 in j.tracks, (disk(t1),))
msgs = j.state.get("userMessages", [])
check("T11 failure reported to the user", any(m.get("messageType", "").startswith("UPLOAD_FAIL") for m in msgs), msgs)
n_before = len(j.tracks)
j.upload("media/garbage.mp3"); j.settle(2)
msgs = j.state.get("userMessages", [])
check("T12 non-audio upload: clear UPLOAD_FAIL_TYPE, nothing left", any(m.get("messageType") == "UPLOAD_FAIL_TYPE" for m in msgs) and len(j.tracks) == n_before
      and not [f for f in os.listdir(DB + "/uploads") if f.startswith("upload_")], msgs)
j.upload("media/sans tags é.mp3"); j.settle(2)
tt = [v for v in j.tracks.values() if v.get("userFilename") == "sans tags é.mp3"]
check("T19 title fallback without extension", tt and tt[0]["title"] == "sans tags é", tt)
j.close()

# ---------- robustness
j = fresh(); pid0 = pid_player()
for typ, payload in (("PLAYLIST_ADD_TRACK", "{}"), ("PLAYLIST_ADD_STREAM", "{}"), ("PLAYLIST_UPDATE", "{}"),
                     ("PLAYLIST_UPDATE", '{"playlist":{"id":"x","tracks":5}}'), ("MESSAGE_DISMISS", '{"id":"a"}'),
                     ("PLAYLIST_NEW", "{not json"), ("TOKEN_EDIT", '{"tagId":5,"name":{}}'), ("PLAYLIST_ADD_UPLOAD", '{"uploadId":"../x"}'),
                     ("SET_VOL", "[]"), ("PLAYLIST_PLAY", '{"playlistId":null}')):
    j.send(typ, payload); time.sleep(0.15)
j.settle(1)
check("T13 malformed messages never crash the player", pid_player() == pid0 and pid0, (pid0, pid_player()))
j.errors.clear(); j.send("GET_STATE", {}); j.settle()
check("T13 player still answers", "db" in j.state)
a = newpl(j, "A"); b = None
before = set(j.pls); j.send("PLAYLIST_NEW", {"title": "B"}); j.send("PLAYLIST_NEW", {"title": "C"}); j.settle(1)
check("T15 two creations in the same second", len(set(j.pls) - before) == 2, set(j.pls) - before)
j.errors.clear(); j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "", "url": "javascript:alert(1)"}); j.settle()
check("T14 invalid radio URL refused", j.errors and not j.pls[a]["tracks"], j.errors)
j.errors.clear()
j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "FIP", "url": "http://icecast.radiofrance.fr/fip-midfi.mp3"})
j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "FIP2", "url": "http://icecast.radiofrance.fr/fip-midfi.mp3"}); j.settle(1)
check("T14 same radio twice", len(j.pls[a]["tracks"]) == 2 and not j.errors, (j.pls[a], j.errors))
s1 = j.pls[a]["tracks"][0]
j.send("PLAYLIST_UPDATE", {"playlist": {"id": a, "tracks": j.pls[a]["tracks"][1:]}}); j.settle()
check("T14 removed radio track is forgotten", s1 not in j.tracks, s1)
s2 = j.pls[a]["tracks"][0]
j.send("PLAYLIST_DELETE", {"playlistId": a}); j.settle()
check("T14b deleting a playlist forgets its radios", s2 not in j.tracks, s2)
j.send("SET_CFG", {"repeat_mode": 0}); j.settle()
cfg = json.load(open(DB + "/audiocfg.json")) if os.path.exists(DB + "/audiocfg.json") else {}
check("T18 repeat mode saved immediately", cfg.get("repeat_mode") == 0, cfg)
# playback: empty playlist token -> no error beep; stale position -> plays
e = newpl(j, "Empty"); j.send("PLAYLIST_UPDATE", {"playlist": {"id": e, "star": "Jooki.Fox"}}); j.settle()
b0 = beeps(); j.nfc(FOX, "101"); j.settle(); j.nfc_off(); j.settle()
check("T16 empty playlist token: no error beep", beeps() == b0, open("/tmp/bench_services.log").read()[-300:])
q = newpl(j, "Q")
for f in ("song4", "song5", "song6"): j.upload("media/%s.mp3" % f, q); j.settle(1.2)
j.send("PLAYLIST_UPDATE", {"playlist": {"id": q, "star": "Jooki.Fox"}}); j.settle()
j.send("PLAYLIST_PLAY", {"playlistId": q, "trackIndex": 3}); j.settle()
j.send("PLAYLIST_UPDATE", {"playlist": {"id": q, "tracks": j.pls[q]["tracks"][:1]}}); j.settle()
b0 = beeps(); j.nfc(FOX, "101"); j.settle()
check("T16 stale resume position still plays", beeps() == b0 and j.state["audio"]["nowPlaying"].get("playlistId") == q, j.state["audio"].get("nowPlaying"))
j.nfc_off(); j.close()

# ---------- persistence across restart
snap = {k: json.load(open("%s/%s.json" % (DB, k))) for k in ("playlists", "tracks", "tokens")}
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
j = Jooki()
check("T20 state survives a restart", set(j.pls) == set(k for k in snap["playlists"] if k != "_") and set(j.tracks) == set(k for k in snap["tracks"] if k != "_"))
j.close()
check("T21 no handler exception in the whole run", open("/tmp/player.log").read().count("ERR_HANDLER") == 0)
bad = [n for n, ok in results if not ok]
print("\n%d/%d passed" % (len(results) - len(bad), len(results)))
sys.exit(1 if bad else 0)
