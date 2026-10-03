"""What every bench suite needs: the fake Jooki (setup.sh), the core started and really up, results
printed the same way, waits with a deadline that say what they waited for, the broker, the logs.
Suites import it (`import bench as B`); nothing here runs on its own."""
import json, os, random, socket, struct, subprocess, sys, threading, time, urllib.request, zlib
import paho.mqtt.client as mqtt
from jk import Jooki, PAGE, WaitTimeout, wait_until, poll

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DB = "/jooki/external/jooki"
PLAYER_LOG, SERVICES_LOG, VOL_LOG = "/tmp/player.log", "/tmp/bench_services.log", "/tmp/bench_vol.log"
WEB_PUBLIC = "/tmp/web_ctrl_dirs/public"          # what the core serves (setup_web_dirs at boot)
PAGE_FILES = "/jooki/app/www/public"              # where deploy_ui.sh puts the page
LUA = os.environ.get("PLAYER_LUA", "core")        # only the core runs on the bench (start_player.sh)

# ------------------------------------------------------------------ results
class Results:
    """PASS/FAIL lines (read by people and by the CI logs), one summary line, the exit code."""
    def __init__(s, limit=300, flush=True, lead="\n"):
        s.R, s.limit, s.flush, s.lead = [], limit, flush, lead
    def check(s, name, ok, info=""):
        ok = bool(ok); s.R.append((name, ok))
        if not ok: info = str(info)[:s.limit] if s.limit else str(info)
        print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  -> " + info), flush=s.flush)
        return ok
    def expect(s, name, cond, t=5, info=None):
        """Wait up to t s for cond() then check it: a check that may still be on its way, never an exception."""
        ok = poll(cond, t)
        if callable(info): info = info()
        return s.check(name, ok, info if info is not None else "still false after %gs" % t)
    def failed(s): return [n for n, ok in s.R if not ok]
    def finish(s, list_failed=False, ok_line=None, on_fail=None):
        bad = s.failed()
        print("%s%d/%d passed" % (s.lead, len(s.R) - len(bad), len(s.R)), flush=True)
        if bad and list_failed: print("FAILED: " + ", ".join(bad), flush=True)
        if bad and on_fail: on_fail()
        if not bad and ok_line: print(ok_line, flush=True)
        sys.exit(1 if bad else 0)

# ------------------------------------------------------------------ the fake Jooki and its core
def enter():
    """Suites run from their own directory (media/, the scripts), wherever they were started from."""
    os.chdir(HERE)

def run(*argv, check=True, env=None, timeout=120):
    """A bench script or tool; its failure is said, not swallowed."""
    r = subprocess.run(argv, capture_output=True, text=True, cwd=HERE, env=env, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError("%s failed (%d): %s" % (" ".join(argv), r.returncode, (r.stderr or r.stdout)[-400:]))
    return r

def setup(seed=False, ui=False, pre=None, truncate=(SERVICES_LOG, VOL_LOG)):
    """A fresh fake Jooki: setup.sh (which also clears /data/openjooki's switches), the demo library
    (seed), the page's files (ui), then `pre` for the suite's own files; the service/volume logs emptied."""
    enter(); run("bash", "setup.sh")
    if seed: run("python3", "seed_demo.py")
    if ui: run("./deploy_ui.sh")
    if pre: pre()
    for f in truncate: open(f, "w").close()

MARK = None          # log mark of the suite's first core start (check_clean_log's default)
def start_core(config=None, t=10):
    """start_player.sh, then the new core really up. Returns the log mark. Three things make it up:
    READY; its bus connection (READY is printed before it connects to the broker: a client asking
    before bus.up gets no answer); its web server. That one normally listens before READY, but a
    background script of the core before it (update check, a security switch) inherits the listening
    socket and may outlive it: the new core then finds 8090 taken and only binds at its 5 s retry.
    Without this wait the page and /upload are refused for those seconds."""
    global MARK
    enter(); mark = log_mark()
    if MARK is None: MARK = mark
    env = dict(os.environ)
    if config: env["OPENJOOKI_CONFIG"] = config
    else: env.pop("OPENJOOKI_CONFIG", None)
    run("./start_player.sh", LUA, env=env)
    wait_log("READY", mark, t); wait_log("bus.up", mark, t)
    try: wait_log("httpd.listening", mark, t + 10)
    except WaitTimeout as e: raise WaitTimeout("%s\n%s" % (e, port_holders(HTTP_PORT)))
    return mark

HTTP_PORT = 8090     # OJ_HTTP_PORT in start_player.sh
def port_holders(port):
    """Who listens on a port (every process sharing the socket), for a failure message."""
    out = subprocess.run("ss -ltnp | grep ':%d '" % port, shell=True, capture_output=True, text=True).stdout.strip()
    pids = sorted(set(x.split("=")[1] for x in out.replace(",", " ").split() if x.startswith("pid=")))
    ps = subprocess.run(["ps", "-o", "pid=,ppid=,etimes=,stat=,args=", "-p", ",".join(pids)], capture_output=True, text=True).stdout.strip() if pids else ""
    return "--- listening on %d: %s\n%s" % (port, out or "nobody", ps)

def boot(seed=False, ui=False, pre=None, config=None, **kw):
    """setup + start_core + a connected Jooki (kw go to Jooki())."""
    setup(seed, ui, pre); start_core(config); return Jooki(**kw)

def restart(j=None, config=None, **kw):
    if j: j.close()
    start_core(config); return Jooki(**kw)

def core_config(d, name):
    """A JSON of config overrides for the core (OPENJOOKI_CONFIG); returns its path, removed at exit."""
    import atexit
    path = "/tmp/oj-%s.json" % name
    json.dump(d, open(path, "w")); atexit.register(lambda: os.path.exists(path) and os.remove(path))
    return path

def _http_ok(url):
    try:
        with urllib.request.urlopen(url, timeout=2) as r: return r.status == 200
    except Exception: return False

def ensure_page():
    """A suite that reads the page as served (test_security) must find it whether or not e2e ran before:
    the page's files deployed, the bench broker (8000 with its password), a core serving them."""
    enter(); fresh = False
    if not os.path.exists(PAGE_FILES + "/oj-auth.json"):
        if not os.path.isdir("/jooki/app/services"): run("bash", "setup.sh")
        run("./deploy_ui.sh"); fresh = True           # the core links the page's files at boot
    start_bench_broker()
    if fresh or not core_pids() or not _http_ok(PAGE + "/oj-auth.json"): start_core()

# ------------------------------------------------------------------ processes
def core_pids():
    out = subprocess.run(["pgrep", "-f", "harness.lua"], capture_output=True, text=True).stdout.split()
    return [int(x) for x in out]
def core_pid():
    p = core_pids(); return p[0] if p else None
def rss_kb(pid):
    try:
        for line in open("/proc/%s/status" % pid):
            if line.startswith("VmRSS"): return int(line.split()[1])
    except OSError: return None
def cpu_ticks(pid):
    f = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])          # utime + stime
def procs(pattern):
    return subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True).stdout.split()

# ------------------------------------------------------------------ the core's log
def log_mark():
    return os.path.getsize(PLAYER_LOG) if os.path.exists(PLAYER_LOG) else 0
def log_since(mark):
    if not os.path.exists(PLAYER_LOG): return ""
    with open(PLAYER_LOG, "rb") as f: f.seek(mark); return f.read().decode(errors="replace")
def wait_log(needle, mark, t=10):
    wait_until(lambda: needle in log_since(mark), t, "%r in %s" % (needle, PLAYER_LOG))
def bad_log_lines(mark):
    """What must never appear: a handler disabled, any error-level line (kernel.log keys)."""
    return [l for l in log_since(mark).splitlines() if "handler_disabled" in l or l.startswith("error")]
def check_clean_log(R, name, mark=None):
    """The log since mark (default: this suite's first core start) has none of them."""
    bad = bad_log_lines(MARK if mark is None else mark)
    return R.check(name, not bad, bad[:3])

# ------------------------------------------------------------------ broker
def wait_port(port, t=5, host="127.0.0.1"):
    def up():
        try: socket.create_connection((host, port), timeout=0.5).close(); return True
        except OSError: return False
    wait_until(up, t, "port %d listening" % port)
def wait_no_proc(pattern, t=5):
    wait_until(lambda: not procs(pattern), t, "no process matching %r" % pattern)
def kill_brokers(t=5):
    subprocess.run(["pkill", "-f", "mosquitto -c"]); wait_no_proc("^mosquitto -c", t)
def start_broker(t=5):
    """The bench broker alone (mosquitto.conf: 1883 anonymous, 8000 WebSocket with the password)."""
    subprocess.Popen(["mosquitto", "-c", os.path.join(HERE, "mosquitto.conf")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_port(1883, t); wait_port(8000, t)
def start_bench_broker(t=5):
    """up.sh: the broker and the fake audio engine, whatever ran before (idempotent)."""
    run("./up.sh"); wait_port(1883, t); wait_port(8000, t)
def restart_broker(down_s=0):
    kill_brokers()
    if down_s: quiet(down_s, "the broker stays away, like a Wi-Fi hiccup")
    start_broker()

# ------------------------------------------------------------------ waits
def quiet(seconds, why):
    """A wait for something NOT to happen: the only fixed sleep allowed, and it says why."""
    time.sleep(seconds)

class Spy:
    """A second bus client that records what the core says (or what the page sends) on some topics."""
    def __init__(s, *topics, name="spy", host="127.0.0.1", port=1883, on=None, t=5):
        s.seen, s.lock, s._sub, s.on = [], threading.Lock(), threading.Event(), on
        s.c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "%s%d" % (name, random.randint(0, 10**6)))
        s.c.on_connect = lambda c, u, f, rc, p=None: c.subscribe([(x, 0) for x in topics])
        s.c.on_subscribe = lambda *a: s._sub.set()
        s.c.on_message = s._msg
        s.c.connect(host, port); s.c.loop_start()
        if not s._sub.wait(t): s.close(); raise WaitTimeout("%s: subscription to %r not acknowledged in %gs" % (name, topics, t))
    def _msg(s, c, u, m):
        p = m.payload.decode(errors="replace")
        with s.lock: s.seen.append((time.time(), m.topic, p))
        if s.on: s.on(m.topic, p, c)
    def mark(s):
        with s.lock: return len(s.seen)
    def since(s, n=0, prefix=""):
        """(topic, payload) pairs recorded from mark n on, under a topic prefix."""
        with s.lock: return [(t, p) for _, t, p in s.seen[n:] if t.startswith(prefix)]
    def payloads(s, topic, n=0): return [p for t, p in s.since(n, topic) if t == topic]
    def last_time(s):
        with s.lock: return s.seen[-1][0] if s.seen else None
    def wait(s, cond, t=5, what=None): return wait_until(cond, t, what)
    def close(s): s.c.loop_stop(); s.c.disconnect()

class Lines:
    """A child's stdout read by a thread, so a wait for a line has a real deadline (readline has none)."""
    def __init__(s, proc):
        s.proc, s.lines, s.eof, s.cv = proc, [], False, threading.Condition()
        threading.Thread(target=s._pump, daemon=True).start()
    def _pump(s):
        for line in s.proc.stdout:
            with s.cv: s.lines.append(line.rstrip("\n")); s.cv.notify_all()
        with s.cv: s.eof = True; s.cv.notify_all()
    def wait(s, needle, t=10):
        """The first line holding needle, or WaitTimeout (also when the child's output ended)."""
        end = time.time() + t; i = 0
        with s.cv:
            while True:
                while i < len(s.lines):
                    if needle in s.lines[i]: return s.lines[i]
                    i += 1
                left = end - time.time()
                if s.eof or left <= 0: break
                s.cv.wait(left)
        raise WaitTimeout("%r not printed in %gs%s; last lines: %r" % (needle, t, " (output ended)" if s.eof else "", s.lines[-5:]))
    def tail(s, n=30):
        with s.cv: return s.lines[-n:]

def wait_line(proc, needle, t=10):
    """proc's stdout must be a PIPE; the reader stays with the proc for the next wait."""
    if not hasattr(proc, "_oj_lines"): proc._oj_lines = Lines(proc)
    return proc._oj_lines.wait(needle, t)

# ------------------------------------------------------------------ media and pages
def ffprobe(path):
    r = subprocess.run(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path], capture_output=True, text=True)
    try: return json.loads(r.stdout)
    except Exception: return {}

def png(w, h, px):
    """A PNG (8-bit RGB) from px(x, y) -> 3 bytes."""
    raw = b"".join(b"\x00" + b"".join(px(x, y) for x in range(w)) for y in range(h))
    def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
PNG_1x1 = png(1, 1, lambda x, y: b"\x00\x00\x00")

def page_diag(pg, j, errs, label):
    """Say why before dying: what the page got, what it said, what the core has."""
    try: html = pg.content()[:1500].replace("\n", " ")
    except Exception as e: html = "(%s)" % e
    try:
        with urllib.request.urlopen(PAGE + "/", timeout=3) as r: http = "%d %s" % (r.status, dict(r.headers).get("Content-Type"))
    except Exception as e: http = str(e)
    print("%s\n  console: %s\n  html: %s\n  core playlists: %s\n  http /: %s" % (label, errs[-10:], html, sorted(j.pls) if j else "-", http), flush=True)
