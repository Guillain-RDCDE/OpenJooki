"""Backend regression tests: real Jooki Lua app (patched) + mosquitto on the bench."""
import json, os, sys
import bench as B
if len(sys.argv) > 1: B.LUA = sys.argv[1]
DB = B.DB
BD1, BD2 = "04000000B00001", "04000000B00003"   # two black dragons (star 262 = 0x106)
FOX = "04000000F00001"                          # fox (257 = 0x101)
R = B.Results(limit=0); check = R.check
def fresh(pre=None): return B.boot(pre=pre)      # a fresh Jooki, the services log emptied
def pid_player(): return B.core_pid()
def beeps(): return open(B.SERVICES_LOG).read().count("errorbeep")
def newpl(j, title): return j.newpl(title, audiobook=False)
def disk(tid): return os.path.exists("%s/uploads/%s" % (DB, tid))
def trash(j): return j.pls.get("TRASH", {}).get("tracks", [])
def msgs(j, kind): return [m for m in j.get("userMessages", []) if (m.get("messageType") or "").startswith(kind)]
def no_tag(j): j.nfc_off(); j.wait(lambda: not j.nfc_state, what="no token on the Jooki")

# ---------- tokens
j = fresh(); p = newpl(j, "Comptines")
j.nfc(BD1, "106"); j.wait(lambda: BD1 in j.tokens); j.nfc_off()
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "star": "Jooki.Black.Dragon"}}); j.wait(lambda: j.pls[p].get("star") == "Jooki.Black.Dragon")
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "  Dark  "}); j.wait(lambda: j.tokens[BD1].get("name") == "Dark")
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "Dark"}); j.barrier()
check("T1 rename twice: no error", j.errors == [], j.errors)
check("T1 name trimmed and saved", j.tokens[BD1].get("name") == "Dark", j.tokens[BD1])
check("T2 naming keeps character link", j.pls[p].get("star") == "Jooki.Black.Dragon" and not j.pls[p].get("tagId"), j.pls[p])
j.upload("media/song1.mp3", p, wait=True)   # a loaded bench imports later: wait for it, not a fixed time
j.nfc(BD2, "106")
R.expect("T2 another black dragon plays it", lambda: j.np.get("playlistId") == p, 5, lambda: j.np)
no_tag(j)
p2 = newpl(j, "Autre")
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p2, "tagId": BD1}}); j.wait(lambda: j.pls[p2].get("star"))
check("T3 old per-token link converted to character link (and unique)",
      j.pls[p2].get("star") == "Jooki.Black.Dragon" and not j.pls[p2].get("tagId") and not j.pls[p].get("star"), (j.pls[p], j.pls[p2]))
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p2, "star": False}}); j.wait(lambda: not j.pls[p2].get("star"))
check("T5 unlink playlist", not j.pls[p2].get("star") and not j.pls[p2].get("tagId"), j.pls[p2])
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "star": "Jooki.Black.Dragon"}}); j.wait(lambda: j.pls[p].get("star"))
j.send("TOKEN_DELETE", {"tagId": BD1}); j.wait(lambda: BD1 not in j.tokens)
check("T6 forgetting a token keeps the playlist link", j.pls[p].get("star") == "Jooki.Black.Dragon" and BD1 not in j.tokens, (j.pls[p], j.tokens))
j.send("TOKEN_EDIT", {"tagId": BD2, "name": "X"}); j.send("TOKEN_EDIT", {"tagId": BD2, "name": ""}); j.barrier()
check("T1b clearing a name", "name" not in j.tokens[BD2], j.tokens[BD2])
check("T1c no errors so far", j.errors == [], j.errors)
# a foreign tag (amiibo, sticker): 2.x only, the 1.x program ignored it
AMIIBO = "046158B2661290"
no_tag(j); j.barrier(); nf0 = dict(j.nfc_state)
j.nfc_foreign(AMIIBO); j.wait(lambda: AMIIBO in j.tokens); j.barrier()
check("TF foreign tag learned as its own character", (j.tokens.get(AMIIBO) or {}).get("starId") == "tag." + AMIIBO, j.tokens.get(AMIIBO))
check("TF foreign tag does not claim to be on the Jooki", dict(j.nfc_state) == nf0, j.nfc_state)
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "star": "tag." + AMIIBO}}); j.wait(lambda: j.pls[p].get("star") == "tag." + AMIIBO)
j.send("DO_PAUSE", {}); j.barrier()
j.nfc_foreign(AMIIBO)
j.poll(lambda: j.pb == "PLAYING", 5)
audio = j.get("audio", {})
check("TF foreign tag starts its playlist", j.np.get("playlistId") == p and j.pb != "PAUSED", audio)
check("TF no errors", j.errors == [], j.errors)
# flat tokens (2.x): one code (512 = 0x200) for all of them, but each one is its own character
CAT, ELE = "04A1B2C3D49C41", "04A1B2C3D477A0"
no_tag(j)
j.nfc(CAT, "200"); j.wait(lambda: CAT in j.tokens); no_tag(j)
j.nfc(ELE, "200"); j.wait(lambda: ELE in j.tokens and j.nfc_state.get("starId") == "flat." + ELE)
check("TFL each flat token is its own character", (j.tokens.get(CAT) or {}).get("starId") == "flat." + CAT
      and (j.tokens.get(ELE) or {}).get("starId") == "flat." + ELE, (j.tokens.get(CAT), j.tokens.get(ELE)))
check("TFL a flat token is on the Jooki like a token", j.nfc_state.get("starId") == "flat." + ELE, j.nfc_state)
no_tag(j)
pc = newpl(j, "Le chat"); pe = newpl(j, "L'éléphant")
j.send("PLAYLIST_UPDATE", {"playlist": {"id": pc, "star": "flat." + CAT}}); j.send("PLAYLIST_UPDATE", {"playlist": {"id": pe, "star": "flat." + ELE}})
j.wait(lambda: j.pls[pc].get("star") and j.pls[pe].get("star"))
j.upload("media/song2.mp3", pc); j.upload("media/song3.mp3", pe)
j.wait(lambda: len(j.pls[pc]["tracks"]) == 1 and len(j.pls[pe]["tracks"]) == 1, 15, "both uploads in")
j.nfc(CAT, "200"); j.poll(lambda: j.np.get("playlistId") == pc, 5)
got_cat = j.np.get("playlistId")
no_tag(j); j.nfc(ELE, "200"); j.poll(lambda: j.np.get("playlistId") == pe, 5)
check("TFL the cat and the elephant start different playlists", got_cat == pc and j.np.get("playlistId") == pe, (got_cat, j.np))
j.poll(lambda: j.pb == "PLAYING", 5)   # really playing, not still starting
j.nfc_off()
R.expect("TFL taking a flat token off pauses", lambda: j.pb == "PAUSED", 5, lambda: j.get("audio.playback"))
# a picture from the page's library; any other address is refused
j.errors.clear(); j.send("TOKEN_EDIT", {"tagId": CAT, "image": "lib:cat_face"}); j.wait(lambda: j.tokens[CAT].get("image") == "lib:cat_face")
check("TFL a library picture for a token", j.tokens[CAT].get("image") == "lib:cat_face" and not j.errors, (j.tokens[CAT], j.errors))
j.send("TOKEN_EDIT", {"tagId": CAT, "image": "https://evil.example/x.png"}); j.wait(lambda: j.errors, what="the refusal")
check("TFL a foreign address is refused", j.tokens[CAT].get("image") == "lib:cat_face" and j.errors, (j.tokens[CAT], j.errors))
j.errors.clear()
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
j.send("TOKEN_EDIT", {"tagId": BD1, "name": "Dark2"}); j.wait(lambda: j.tokens[BD1].get("name") == "Dark2")
check("T1d image preserved on rename", j.tokens[BD1].get("image") == "custom.png", j.tokens[BD1])
j.close()

# ---------- TRASH and data safety
j = fresh(); p = newpl(j, "P")
j.upload("media/song1.mp3", wait=True)
t1 = [k for k in j.tracks][0]
check("T7 upload without playlist appears in Unused tracks at once", trash(j) == [t1], j.pls)
for payload in ({"id": "TRASH", "title": "Test"}, {"id": "TRASH", "star": "Jooki.Dragon"}):
    j.errors.clear(); j.send("PLAYLIST_UPDATE", {"playlist": payload}); j.wait(lambda: j.errors, what="the refusal")
    check("T7 TRASH refuses %s" % list(payload)[1], j.errors and j.errors[-1]["msg"] == "TRASH_READONLY" and j.pls["TRASH"].get("title") == "Unused tracks" and not j.pls["TRASH"].get("star"), (j.errors, j.pls["TRASH"]))
j.errors.clear(); j.send("PLAYLIST_DELETE", {"playlistId": "TRASH"}); j.wait(lambda: j.errors, what="the refusal")
check("T7 TRASH cannot be deleted", "TRASH" in j.pls and j.errors, j.errors)
j.errors.clear(); j.send("PLAYLIST_ADD_TRACK", {"playlistId": "TRASH", "trackId": t1}); j.wait(lambda: j.errors, what="the refusal")
check("T7 nothing can be added to TRASH", j.errors and trash(j) == [t1], (j.errors, trash(j)))
j.send("PLAYLIST_ADD_TRACK", {"playlistId": p, "trackId": t1}); j.wait(lambda: j.pls[p]["tracks"] == [t1])
check("T8 used track leaves Unused tracks immediately", "TRASH" not in j.pls and j.pls[p]["tracks"] == [t1], j.pls)
j.upload("media/song2.mp3", wait=True)
t2 = [k for k in j.tracks if k != t1][0]
# stale client: asks TRASH to keep nothing, while t1 is used by P
j.send("PLAYLIST_UPDATE", {"playlist": {"id": "TRASH", "tracks": []}}); j.wait(lambda: t2 not in j.tracks)
check("T8 emptying Unused tracks deletes only unused files", disk(t1) and t1 in j.tracks and not disk(t2) and t2 not in j.tracks, (disk(t1), disk(t2)))
j.upload("media/song3.mp3", p, wait=True)
t3 = [k for k in j.pls[p]["tracks"] if k != t1][0]
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "tracks": [t3]}}); j.wait(lambda: j.pls[p]["tracks"] == [t3])
check("T9 track removed from a playlist goes to Unused tracks (file kept)", trash(j) == [t1] and disk(t1), (trash(j), disk(t1)))
j.send("PLAYLIST_UPDATE", {"playlist": {"id": p, "tracks": [t3, "deadbeefdeadbeef"]}}); j.barrier()
check("T9b unknown track ids ignored", j.pls[p]["tracks"] == [t3], j.pls[p])
j.send("PLAYLIST_DELETE", {"playlistId": p}); j.wait(lambda: p not in j.pls)
check("T10 deleting a playlist sends its tracks to Unused tracks", sorted(trash(j)) == sorted([t1, t3]) and disk(t3), trash(j))
# duplicate upload to a missing playlist must not delete the existing file
j.errors.clear(); n = len(msgs(j, "UPLOAD_FAIL")); j.upload("media/song1.mp3", "user_doesnotexist")
j.wait(lambda: len(msgs(j, "UPLOAD_FAIL")) > n, 15, "the upload's failure reported")
check("T11 failed duplicate upload keeps the existing file", disk(t1) and t1 in j.tracks, (disk(t1),))
check("T11 failure reported to the user", any(m.get("messageType", "").startswith("UPLOAD_FAIL") for m in j.get("userMessages", [])), j.get("userMessages"))
n_before = len(j.tracks)
n = len(msgs(j, "UPLOAD_FAIL_TYPE")); j.upload("media/garbage.mp3")
j.wait(lambda: len(msgs(j, "UPLOAD_FAIL_TYPE")) > n and not [f for f in os.listdir(DB + "/uploads") if f.startswith("upload_")], 15, "the garbage refused and its file gone")
check("T12 non-audio upload: clear UPLOAD_FAIL_TYPE, nothing left", any(m.get("messageType") == "UPLOAD_FAIL_TYPE" for m in j.get("userMessages", [])) and len(j.tracks) == n_before
      and not [f for f in os.listdir(DB + "/uploads") if f.startswith("upload_")], j.get("userMessages"))
j.upload("media/sans tags é.mp3", wait=True)
tt = [v for v in j.tracks.values() if v.get("userFilename") == "sans tags é.mp3"]
check("T19 title fallback without extension", tt and tt[0]["title"] == "sans tags é", tt)
j.close()

# ---------- robustness
j = fresh(); pid0 = pid_player()
for typ, payload in (("PLAYLIST_ADD_TRACK", "{}"), ("PLAYLIST_ADD_STREAM", "{}"), ("PLAYLIST_UPDATE", "{}"),
                     ("PLAYLIST_UPDATE", '{"playlist":{"id":"x","tracks":5}}'), ("MESSAGE_DISMISS", '{"id":"a"}'),
                     ("PLAYLIST_NEW", "{not json"), ("TOKEN_EDIT", '{"tagId":5,"name":{}}'), ("PLAYLIST_ADD_UPLOAD", '{"uploadId":"../x"}'),
                     ("SET_VOL", "[]"), ("PLAYLIST_PLAY", '{"playlistId":null}')):
    j.send(typ, payload)
alive = j.alive()      # answered after all of the above (same connection: handled in order)
check("T13 malformed messages never crash the player", pid_player() == pid0 and pid0, (pid0, pid_player()))
j.errors.clear()
check("T13 player still answers", alive)
a = newpl(j, "A")
before = set(j.pls); j.send("PLAYLIST_NEW", {"title": "B"}); j.send("PLAYLIST_NEW", {"title": "C"})
R.expect("T15 two creations in the same second", lambda: len(set(j.pls) - before) == 2, 5, lambda: set(j.pls) - before)
j.errors.clear(); j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "", "url": "javascript:alert(1)"}); j.wait(lambda: j.errors, what="the refusal")
check("T14 invalid radio URL refused", j.errors and not j.pls[a]["tracks"], j.errors)
j.errors.clear()
j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "FIP", "url": "http://icecast.radiofrance.fr/fip-midfi.mp3"})
j.send("PLAYLIST_ADD_STREAM", {"playlistId": a, "title": "FIP2", "url": "http://icecast.radiofrance.fr/fip-midfi.mp3"}); j.wait(lambda: len(j.pls[a]["tracks"]) == 2)
check("T14 same radio twice", len(j.pls[a]["tracks"]) == 2 and not j.errors, (j.pls[a], j.errors))
s1 = j.pls[a]["tracks"][0]
j.send("PLAYLIST_UPDATE", {"playlist": {"id": a, "tracks": j.pls[a]["tracks"][1:]}}); j.wait(lambda: s1 not in j.tracks)
check("T14 removed radio track is forgotten", s1 not in j.tracks, s1)
s2 = j.pls[a]["tracks"][0]
j.send("PLAYLIST_DELETE", {"playlistId": a}); j.wait(lambda: s2 not in j.tracks)
check("T14b deleting a playlist forgets its radios", s2 not in j.tracks, s2)
def audiocfg(): return json.load(open(DB + "/audiocfg.json")) if os.path.exists(DB + "/audiocfg.json") else {}
j.send("SET_CFG", {"repeat_mode": 0}); B.poll(lambda: audiocfg().get("repeat_mode") == 0, 5)
check("T18 repeat mode saved immediately", audiocfg().get("repeat_mode") == 0, audiocfg())
# playback: empty playlist token -> no error beep; stale position -> plays
e = newpl(j, "Empty"); j.send("PLAYLIST_UPDATE", {"playlist": {"id": e, "star": "Jooki.Fox"}}); j.wait(lambda: j.pls[e].get("star"))
b0 = beeps(); j.nfc(FOX, "101"); j.wait(lambda: j.nfc_state.get("starId") == "Jooki.Fox"); j.barrier(); j.nfc_off()
B.quiet(0.5, "an error beep, had the core asked for one, would be in the services log by now")
check("T16 empty playlist token: no error beep", beeps() == b0, open(B.SERVICES_LOG).read()[-300:])
q = newpl(j, "Q")
for f in ("song4", "song5", "song6"): j.upload("media/%s.mp3" % f, q, wait=True)
j.send("PLAYLIST_UPDATE", {"playlist": {"id": q, "star": "Jooki.Fox"}}); j.wait(lambda: j.pls[q].get("star"))
j.send("PLAYLIST_PLAY", {"playlistId": q, "trackIndex": 3}); j.wait(lambda: j.np.get("trackIndex") == 3)
j.send("PLAYLIST_UPDATE", {"playlist": {"id": q, "tracks": j.pls[q]["tracks"][:1]}}); j.wait(lambda: len(j.pls[q]["tracks"]) == 1)
b0 = beeps(); j.nfc(FOX, "101"); j.wait(lambda: j.np.get("playlistId") == q)
B.quiet(0.5, "an error beep, had the core asked for one, would be in the services log by now")
check("T16 stale resume position still plays", beeps() == b0 and j.np.get("playlistId") == q, j.np)
j.nfc_off(); j.close()

# ---------- persistence across restart
snap = {k: json.load(open("%s/%s.json" % (DB, k))) for k in ("playlists", "tracks", "tokens")}
j = B.restart()
check("T20 state survives a restart", set(j.pls) == set(k for k in snap["playlists"] if k != "_") and set(j.tracks) == set(k for k in snap["tracks"] if k != "_"))
j.close()
B.check_clean_log(R, "T21 no handler exception in the whole run")
R.finish()
