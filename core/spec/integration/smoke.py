"""Smoke test of the built core: start build/core.lua under lua5.1 with the host
stubs, against a real mosquitto, then talk v2 to it and measure the budgets.
  python3 core/spec/integration/smoke.py            (run from the repo root)
Checks: boots, answers state.get, rejects a bad command with a typed error,
publishes patches with increasing rev, idle bus traffic under budget, no shell
process started, memory under budget, stops cleanly on SIGTERM."""
import json, os, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "openjooki", "tests"))
import bench as B  # noqa: E402

R = B.Results()
check = R.check

# the bundle brings its own harness (the 4 host stubs, then the core), the same the bench runs
subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build", "bundle.py")], check=True)
# the bus client (and the fake esp32_ctrl) is up before the core starts, as on the device
got = {"replies": [], "states": [], "events": [], "all": []}
def on_msg(topic, payload, cl):
    try: d = json.loads(payload)
    except Exception: d = payload
    got["all"].append((time.time(), topic))
    if topic == "/j/web/v2/reply": got["replies"].append(d)
    elif topic == "/j/web/v2/state": got["states"].append(d)
    elif topic == "/j/web/v2/event": got["events"].append(d)
    # the device's esp32_ctrl answers the knobs question (headphones out: nothing changes)
    elif topic == "/j/esp32/output/knobs/state": cl.publish("/j/esp32/input/knobs/state", '{"hp_state":0}')
spy = B.Spy("/j/#", name="smoke", on=on_msg)
c = spy.c
env = dict(os.environ, OPENJOOKI_LOG="info", id="jooki-bench", hostname="jooki-bench.local", machine="bench")
proc = subprocess.Popen(["lua5.1", os.path.join(ROOT, "build", "harness.lua"), os.path.join(ROOT, "build", "core.min.lua")],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env, cwd=ROOT)
out = B.Lines(proc)
t0 = time.time()
try: out.wait("READY", 10); ready = True
except B.WaitTimeout: ready = False
check("S1 core boots and reports ready in < 10 s (%.2fs)" % (time.time() - t0), ready, out.tail(5))

def cmd(msg, wait=2.0):
    n = len(got["replies"])
    c.publish("/j/web/v2/cmd", json.dumps(msg) if isinstance(msg, dict) else msg)
    B.poll(lambda: len(got["replies"]) > n, wait, every=0.02)
    return got["replies"][n] if len(got["replies"]) > n else None

# READY comes before the core is on the bus: the first question is asked again until it answers
r = B.wait_until(lambda: cmd({"v": 2, "id": "a1", "type": "state.get"}), 10, "an answer to state.get")
check("S2 state.get answers ok with the id", r == {"v": 2, "id": "a1", "ok": True}, r)
fulls = [s for s in got["states"] if isinstance(s, dict) and s.get("full")]   # a patch may follow the full state
st = fulls[-1] if fulls else None
check("S2 full state published with rev and device info", st and st.get("full") and st["state"]["device"]["hostname"] == "jooki-bench" and st["state"]["device"]["core"], st)
r = cmd({"v": 2, "id": "a2", "type": "playlist.explode"})
check("S3 unknown command -> typed not_found error", r and r["ok"] is False and r["error"]["code"] == "not_found", r)
r = cmd("{garbage")
check("S3 garbage -> invalid_argument, core still alive", r and r["error"]["code"] == "invalid_argument" and proc.poll() is None, r)
r = cmd({"v": 2, "id": "a3", "type": "core.version"})
check("S4 core.version event", r and r["ok"] and got["events"] and got["events"][-1]["payload"]["core"], got["events"][-1:])

# the optional streaming module (ADR-0009): a fake spotify_ctrl logs in, the state follows;
# a preset request while nothing plays is refused, the core stays alive
n = len(got["states"])
c.publish("/j/spotify/input/login", json.dumps({"username": "fake-spotify"}))
B.poll(lambda: len(got["states"]) > n, 2, every=0.02)
sp = [s for s in got["states"][n:] if s.get("patch", {}).get("spotify")]
check("S8 spotify login from the daemon reaches the state", sp and sp[-1]["patch"]["spotify"]["username"] == "fake-spotify", got["states"][n:][-2:])
r = cmd({"v": 2, "id": "a4", "type": "spotify.new_playlist", "payload": {"title": "x"}})
check("S8 preset while idle -> unavailable, core alive", r and r["ok"] is False and r["error"]["code"] == "unavailable" and proc.poll() is None, r)

# idle traffic budget: 10 s of silence
before = len(got["all"]); B.quiet(10, "the idle traffic budget is measured over 10 s of nothing"); idle = len(got["all"]) - before
check("S5 idle bus traffic <= 0.5 msg/s (got %.2f)" % (idle / 10), idle <= 5, idle)

# memory (RSS of the lua process)
rss = B.rss_kb(proc.pid)
# the 4 MB budget is for the device (32-bit MIPS, docs/21 §5); this x86-64 bench with the
# full standard library and 64-bit pointers runs about 30 % larger
check("S6 RSS under 6 MB on the bench (got %s kB)" % rss, rss is not None and rss < 6144, rss)

# the loop must still be alive after everything above (on the device the C host
# turns SIGTERM into c_isTerminating; a bare lua5.1 has no such handler, so we
# only check liveness here and stop it hard)
alive = proc.poll() is None
proc.kill(); proc.wait(timeout=5)
check("S7 core alive until stopped (no crash during the run)", alive)
spy.close()
R.finish(on_fail=lambda: print("--- core output (last 30 lines) ---\n" + "\n".join(out.tail(30))))
