"""Endurance run of the built core on the bench (docs/21 §14).
  python3 core/spec/integration/endurance.py [minutes]        (default 10; run from tools/openjooki/tests as root)
Random tokens, transport, uploads, page commands, broker restarts and clock
jumps for the given duration; then checks: the core never died, no handler
was disabled, memory did not grow (last third vs first third), and the
library is still consistent (every playlist track exists, no orphan file)."""
import json, os, random, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
TESTS = "/root/oj/tests" if os.path.isdir("/root/oj/tests") else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tools", "openjooki", "tests")
sys.path.insert(0, TESTS); os.chdir(TESTS)
from jk import Jooki

MINUTES = float(sys.argv[1]) if len(sys.argv) > 1 else 10
DB = "/jooki/external/jooki"
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]), flush=True)

def pid():
    return subprocess.run(["pgrep", "-f", "^lua5.1 .*harness"], capture_output=True, text=True).stdout.split()
def rss(p):
    try:
        for line in open("/proc/%s/status" % p):
            if line.startswith("VmRSS"): return int(line.split()[1])
    except Exception: return None

subprocess.run(["bash", "setup.sh"], capture_output=True)
subprocess.run(["python3", "seed_demo.py"], capture_output=True)
open("/tmp/player.log", "w").close()
subprocess.run(["./start_player.sh", "core"], capture_output=True); time.sleep(1.5)
p0 = pid()
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
        subprocess.run(["pkill", "-f", "^mosquitto -c"]); time.sleep(3)
        subprocess.Popen(["mosquitto", "-c", "mosquitto.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True); time.sleep(2)
        try: j.close()
        except Exception: pass
        j = Jooki()
        next_restart = time.time() + 120
    time.sleep(rnd.uniform(0.05, 0.4))
    if n_ops % 50 == 0:
        p = pid()
        if p: samples.append(rss(p[0]))

p1 = pid()
check("E1 the same core process survived %d operations and %d broker restarts" % (n_ops, int(MINUTES * 60 / 120)), p1 == p0, (p0, p1))
j.send("GET_STATE", {}); j.wait(lambda: "db" in j.state, 5)
health = j.state.get("device", {})
log = open("/tmp/player.log").read()
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
bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
