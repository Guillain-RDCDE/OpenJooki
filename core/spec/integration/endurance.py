"""Endurance run of the built core on the bench (docs/21 §14).
  python3 core/spec/integration/endurance.py [minutes]        (default 10; as root, from anywhere)
Random tokens, transport, uploads, page commands, broker restarts and clock
jumps for the given duration; then checks: the core never died, no handler
was disabled, memory did not grow (last third vs first third), and the
library is still consistent (every playlist track exists, no orphan file)."""
import json, os, random, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tools", "openjooki", "tests"))
import bench as B  # noqa: E402
from jk import Jooki  # noqa: E402

MINUTES = float(sys.argv[1]) if len(sys.argv) > 1 else 10
DB = B.DB
R = B.Results()
check = R.check

B.setup(seed=True)
mark = B.start_core()          # the log from here on is this run's
p0 = B.core_pids()
check("E0 core started", len(p0) == 1, p0)
j = Jooki()
pls = [k for k in j.pls if k not in ("TRASH", "system")]
TOKENS = [("04000000D00001", "100"), ("04000000F00001", "101"), ("04000000G00001", "102"), ("04000000K00001", "103"), ("04000000W00001", "105"), ("04000000B00001", "106"), ("04000000A00001", "211"), ("04000000Z00099", "fff")]
rnd = random.Random(42)
samples = []
t_end = time.time() + MINUTES * 60
n_ops = 0
next_restart = time.time() + 120
while time.time() < t_end:
    op = rnd.random()
    if op < 0.30:
        uid, star = rnd.choice(TOKENS); j.nfc(uid, star)
    elif op < 0.45:
        j.nfc_off()
    elif op < 0.60:
        j.send(rnd.choice(["DO_NEXT", "DO_PREV", "DO_PAUSE", "DO_PLAY"]), {})
    elif op < 0.70:
        j.send("SET_VOL", {"vol": rnd.randint(0, 100)})
    elif op < 0.78:
        j.send("PLAYLIST_PLAY", {"playlistId": rnd.choice(pls), "trackIndex": rnd.randint(1, 5)})
    elif op < 0.84:
        j.upload("media/song%d.mp3" % rnd.randint(1, 6), rnd.choice(pls))
    elif op < 0.88:
        j.send("OJ_SLEEP", rnd.choice([{"seconds": rnd.randint(3, 20)}, {"mode": "track"}, {"cancel": True}]))
    elif op < 0.92:
        j.send(rnd.choice(["PLAYLIST_UPDATE", "TOKEN_EDIT", "SEEK", "MESSAGE_DISMISS"]), rnd.choice(["{", "[]", "{\"x\":1}", "{\"playlist\":{\"id\":5}}"]))
    elif op < 0.96:
        j.c.publish("/j/audio/input/ended", json.dumps({"id": 7}))
    else:
        j.send("GET_STATE", {})
    n_ops += 1
    if time.time() > next_restart:   # the broker goes away for a few seconds, like a Wi-Fi hiccup
        B.restart_broker(down_s=3)
        try: j.close()
        except Exception: pass
        j = Jooki(timeout=30)        # the core comes back on its own backoff (up to 16 s after a 3 s outage)
        next_restart = time.time() + 120
    time.sleep(rnd.uniform(0.05, 0.4))
    if n_ops % 50 == 0:
        p = B.core_pids()
        if p: samples.append(B.rss_kb(p[0]))

p1 = B.core_pids()
check("E1 the same core process survived %d operations and %d broker restarts" % (n_ops, int(MINUTES * 60 / 120)), p1 == p0, (p0, p1))
j.refresh()
log = B.log_since(mark)
check("E2 no handler disabled", "handler_disabled" not in log)
errs = [l for l in log.splitlines() if l.startswith("error")]
check("E3 fewer than %d error lines (%d)" % (max(10, n_ops // 20), len(errs)), len(errs) < max(10, n_ops // 20), errs[:5])
if len(samples) >= 6:
    third = len(samples) // 3
    first, last = sum(samples[:third]) / third, sum(samples[-third:]) / third
    check("E4 memory flat: first third %.0f kB, last third %.0f kB" % (first, last), last < first * 1.25 and last < 8192, samples)
else:
    check("E4 memory samples collected", False, samples)
# library consistency
lib = j.state["db"]
missing = [t for p in lib["playlists"].values() for t in p.get("tracks", []) if t not in lib["tracks"]]
files = set(os.listdir(DB + "/uploads"))
orphans = [f for f in files if f not in lib["tracks"] and not f.startswith("upload_")]
nofile = [t for t, v in lib["tracks"].items() if not v.get("isUrl") and not os.path.exists(v.get("filename", ""))]
check("E5 library consistent (no unknown track in a playlist, no orphan file, no track without file)", not missing and not orphans and not nofile, (missing, orphans[:3], nofile[:3]))
j.close()
R.finish()
