"""A safer start, on the bench (real core): what keeps the Jooki alive when a piece fails.
  R1  no broker: the core waits its turns, it does not spin and burn the CPU (and the battery)
  R2  the broker killed: the core starts it again by itself (adapters.broker_watch), then reconnects
  R3  the maintenance SSH key: kept on /data (updates rewrite /home), only while the access is open
  R4  the page shows the key field while the access is open
Run last in a chain: R2 leaves a broker started from /etc/mosquitto; up.sh puts the bench one back.
  python3 test_robustness.py"""
import json, os, subprocess, sys, time
from jk import Jooki, PAGE
LUA = os.environ.get("PLAYER_LUA", "core")
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]), flush=True)
def sh(cmd): return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout
def core_pid():
    out = sh("pgrep -f 'harness.lua' | head -n 1").strip()
    return int(out) if out else None
def cpu_ticks(pid):
    f = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])          # utime + stime
def kill_brokers():
    sh("pkill -f 'mosquitto -c'"); time.sleep(0.5)

KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq7T1kq0rQw0Yl2m1nV4p9ZxKqvB0cVd7mH3sJk2LtR bench@openjooki"
KEYS, HOME_KEYS = "/data/openjooki/authorized_keys", "/home/root/.ssh/authorized_keys"

subprocess.run(["bash", "setup.sh"], capture_output=True)
kill_brokers(); subprocess.run(["./up.sh"], capture_output=True)   # the bench broker (with its WebSocket), whatever ran before
subprocess.run(["./deploy_ui.sh"], capture_output=True)   # before the core: it links the page's files at boot
os.makedirs("/data/openjooki", exist_ok=True)
for f in (KEYS, HOME_KEYS, "/data/openjooki/parent_code"):
    try: os.remove(f)
    except OSError: pass
# the broker watch is on on the device; on the bench only when asked: 3 s instead of 20
cfg = "/tmp/oj-robustness.json"
json.dump({"broker_watch_s": 3}, open(cfg, "w"))
os.environ["OPENJOOKI_CONFIG"] = cfg
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(2)

# --- R3 / R4 first, while the bench broker is up -------------------------------------------
j = Jooki()
def maint(): return j.state.get("maintenance", {}) if isinstance(j.state.get("maintenance"), dict) else {}
def last_error(): return (j.errors[-1] or {}).get("msg") if j.errors else None
j.send("OJ_SSH_KEY", {"key": KEY}); time.sleep(0.8)
check("R3 a key is refused while the maintenance access is closed", last_error() == "SSH_CLOSED" and not os.path.exists(KEYS), (j.errors[-2:], os.path.exists(KEYS)))
j.send("OJ_SSH_ON", {}); j.wait(lambda: maint().get("ssh") is True, 5)
j.send("OJ_SSH_KEY", {"key": "ssh-rsa not-a-key; reboot"}); time.sleep(0.8)
check("R3 something that is not a public key is refused", last_error() == "SSH_KEY_INVALID" and not os.path.exists(KEYS), j.errors[-2:])
j.send("OJ_SSH_KEY", {"key": "  " + KEY + "\n"}); j.wait(lambda: os.path.exists(KEYS) and maint().get("ssh_keys") == 1, 5)
kept = open(KEYS).read() if os.path.exists(KEYS) else ""
home = open(HOME_KEYS).read() if os.path.exists(HOME_KEYS) else ""
check("R3 the key is kept on /data and put in place for dropbear", kept == KEY + "\n" and home == kept and maint().get("ssh_keys") == 1, (kept, home, maint()))
mode = oct(os.stat(KEYS).st_mode & 0o777) if os.path.exists(KEYS) else None
check("R3 ... readable by root only", mode == "0o600", mode)
j.send("OJ_SSH_KEY", {"key": KEY}); time.sleep(0.8)
check("R3 the same key twice is kept once", open(KEYS).read().count("\n") == 1, open(KEYS).read())

# R4: the field on the page, only while the access is open
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 390, "height": 844}, locale="fr-FR")
        pg.goto(PAGE + "/#/settings/maintenance")   # since 2.2 each topic has its own page
        pg.wait_for_selector("[data-k=ssh]", timeout=15000)
        shown = pg.locator("[data-k=sshkey]").count() == 1 and "1 clé enregistrée" in pg.locator("body").inner_text()
        check("R4 the page shows the key field and the saved key while the access is open", shown, pg.locator("body").inner_text()[-600:])
        j.send("OJ_SSH_KEY", {"clear": True}); j.wait(lambda: maint().get("ssh_keys") == 0, 5)
        check("R3 'forget the keys' removes both files", not os.path.exists(KEYS) and not os.path.exists(HOME_KEYS), (os.path.exists(KEYS), os.path.exists(HOME_KEYS)))
        j.send("OJ_SSH_OFF", {}); j.wait(lambda: maint().get("ssh") is False, 5)
        try: pg.wait_for_function("!document.querySelector('[data-k=sshkey]')", timeout=5000)
        except Exception: pass
        check("R4 ... and hides it once the access is closed", pg.locator("[data-k=sshkey]").count() == 0)
        b.close()
except ImportError:
    print("SKIP R4 (no playwright)")
j.close()

# --- R1: no broker, no spinning ------------------------------------------------------------
pid = core_pid()
kill_brokers()
time.sleep(1.5)
t0, c0 = time.time(), cpu_ticks(pid)
time.sleep(1.0)                       # within the 3 s before the watch acts
used = (cpu_ticks(pid) - c0) / os.sysconf("SC_CLK_TCK") / (time.time() - t0)
check("R1 without a broker the core does not spin (CPU %.0f %%)" % (used * 100), used < 0.2, used)

# --- R2: the broker comes back by itself ---------------------------------------------------
if not os.path.exists("/etc/mosquitto/mosquitto.conf"):
    os.makedirs("/etc/mosquitto", exist_ok=True)
    open("/etc/mosquitto/mosquitto.conf", "w").write("listener 1883 127.0.0.1\nallow_anonymous true\n")
started = False
for _ in range(40):
    time.sleep(0.5)
    if "mosquitto -c /etc/mosquitto/mosquitto.conf" in sh("ps -eo args"):
        started = True; break
check("R2 the core started the broker again by itself", started, sh("ps -eo args | grep -i mosq"))
# the core reconnects on its own backoff (a few seconds): ask until it answers
back, t0 = False, time.time()
while not back and time.time() - t0 < 30:
    try:
        j2 = Jooki()
        back = "db" in j2.state
        j2.close()
    except Exception as e:
        print("  connect:", e); time.sleep(1)
check("R2 ... and everything talks again (the page gets its state, after %.0f s)" % (time.time() - t0), back)
check("R1 the core is still the same process", core_pid() == pid, (pid, core_pid()))

# --- R5: the boot loop runs our start scripts, never the originals kept next to them ----------
import tempfile
d = tempfile.mkdtemp()
os.makedirs(d + "/rcS.d"); os.makedirs(d + "/rc5.d")
for n in ("S55_ml-start-wifi.sh", "S58_mosquitto.sh"):
    open(d + "/rcS.d/" + n, "w").write("echo RAN %s\n" % n)
    open(d + "/rcS.d/" + n + ".openjooki-orig", "w").write("#!/bin/sh\necho RAN-ORIGINAL %s\n" % n)
    os.chmod(d + "/rcS.d/" + n + ".openjooki-orig", 0o755)
rcs = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "system", "rcS")).read().replace("\r", "")
open(d + "/rcS", "w").write(rcs.replace("/etc/rcS.d", d + "/rcS.d").replace("/etc/rc5.d", d + "/rc5.d").replace("/dev/kmsg", d + "/kmsg-none"))
ran = sh("sh %s/rcS" % d)
check("R5 the boot loop runs the new start scripts", "RAN S55_ml-start-wifi.sh" in ran and "RAN S58_mosquitto.sh" in ran, ran)
check("R5 ... and never the originals kept next to them", "RAN-ORIGINAL" not in ran, ran)

# back to the bench broker for whatever runs next
kill_brokers()
os.environ.pop("OPENJOOKI_CONFIG", None)
subprocess.run(["./up.sh"], capture_output=True)
subprocess.run(["./start_player.sh", LUA], capture_output=True)
for f in (cfg,):
    try: os.remove(f)
    except OSError: pass
bad = [n for n, ok in R if not ok]
print("%d/%d passed" % (len(R) - len(bad), len(R)))
sys.exit(1 if bad else 0)
