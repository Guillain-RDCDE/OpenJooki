#!/usr/bin/env python3
"""A Wi-Fi chip firmware on trial (system/oj-esp32-trial.sh, docs/32): written at the start, judged,
and the original firmware written back by itself whenever anything is wrong.

The real script runs under busybox ash. The Jooki's installer is a stand-in that "writes" the chip
(a file holding which package it was given) and can fail, or stop the Jooki in the middle; df,
logger, sync and reboot are stand-ins too. The chip's answer and the Wi-Fi route are files the
test changes. Times are shortened.
  python3 test_esp32_trial.py
"""
import hashlib, os, shutil, stat, subprocess, tempfile, time
import bench as B

R = B.Results(); check = R.check
SCRIPT = os.path.join(B.REPO, "tools", "openjooki", "system", "oj-esp32-trial.sh")
S55 = os.path.join(B.REPO, "tools", "openjooki", "system", "S55_ml-start-wifi.sh")
BUSYBOX = shutil.which("busybox")
SRC = open(SCRIPT).read()
CANDIDATE = SRC.split("\nCANDIDATE=")[1].split("\n")[0]
STOCK = SRC.split("\nSTOCK=")[1].split("\n")[0]
ROUTE = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n" \
        "ethsta0\t00000000\t0101A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
TOOLS = {
    # the Jooki's installer: "writes" the chip with the package it is given, as told by $T/flash
    # (one word per call: ok, fail, or die = the Jooki stops in the middle of the write)
    "installer": 'n=$(cat "$T/inst_n" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$T/inst_n"\n'
                 'echo "$1" >> "$T/inst.log"\n'
                 'w=$(sed -n "${n}p" "$T/flash"); [ -n "$w" ] || w=ok\n'
                 'echo garbage > "$T/chip"\n'
                 # the chip is left in download mode while it writes, as the real installer does
                 'echo -n 1 > "$T/htdrv/esp_bootmode"\n'
                 'case $w in die) kill -9 $PPID; exit 9 ;; fail) exit 1 ;; esac\n'
                 'sha256sum "$1" | cut -d" " -f1 > "$T/chip"\n'
                 'echo -n 0 > "$T/htdrv/esp_bootmode"\n',
    "df": 'printf "Filesystem 1K-blocks Used Available Use%% Mounted on\\n/dev/mmcblk0p5 100000 1 %s 1%% /data\\n" '
          '"$(cat "$T/free" 2>/dev/null || echo 50000)"\n',
    "logger": 'echo "$*" >> "$T/syslog"\n',
    "sync": ':\n',
    "reboot": 'date +%s > "$T/rebooted"\n',
}


class Jooki:
    def __init__(self, stock_ok=True, api="0x0204", loaded=True, alive=True, wifi=True):
        self.t = t = tempfile.mkdtemp(prefix="oj-esp32-")
        self.bin = os.path.join(t, "bin"); os.mkdir(self.bin)
        for name, body in TOOLS.items():
            p = os.path.join(self.bin, name)
            with open(p, "w") as f: f.write("#!%s ash\nT=%s\n%s" % (BUSYBOX, t, body))
            os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
        for applet in ("sed", "cat", "tail", "head", "sleep", "mkdir", "rm", "mv", "cp", "date", "touch", "grep",
                       "awk", "cut", "sha256sum", "tar", "gzip", "echo", "kill", "printf"):
            os.symlink(BUSYBOX, os.path.join(self.bin, applet))
        for d in ("data/mode", "data/openjooki", "etc/esp32", "htdrv", "pkg"):
            os.makedirs(os.path.join(t, d))
        # the packages: small real tar.gz, pinned by their SHA-256 in the script (the test re-pins them)
        self.cand = self.package("candidate")
        self.stock_etc = os.path.join(t, "etc/esp32/factory_default_firmware.tgz")
        shutil.copy(self.package("stock") if stock_ok else self.package("other"), self.stock_etc)
        self.script = os.path.join(t, "oj-esp32-trial")
        src = SRC.replace("\nCANDIDATE=" + CANDIDATE + "\n", "\nCANDIDATE=%s\n" % self.sha(self.cand))
        src = src.replace("\nSTOCK=" + STOCK + "\n", "\nSTOCK=%s\n" % self.sha(self.package("stock")))
        with open(self.script, "w") as f: f.write(src)
        self.write("etc/esp32/esp_fw_version.rc", 'ESP32_FW_API_VERSION="%s"\n' % api)
        if loaded: self.write("data/mode/ESP32_FIRMWARE_LOADED", "")
        self.write("chip", self.sha(self.stock_etc) + "\n")
        self.set(alive=alive, wifi=wifi)
        self.env = {"OJ_ESP_PATH": self.bin, "OJ_ESP_DATA": os.path.join(t, "data"), "OJ_ESP_STOCK": self.stock_etc,
                    "OJ_ESP_INSTALLER": os.path.join(self.bin, "installer"),
                    "OJ_ESP_API_RC": os.path.join(t, "etc/esp32/esp_fw_version.rc"),
                    "OJ_ESP_FW_VERSION": os.path.join(t, "fw_version"), "OJ_ESP_ROUTES": os.path.join(t, "route"),
                    "OJ_ESP_HTDRV": os.path.join(t, "htdrv"), "OJ_ESP_WIFI_S": "3", "OJ_ESP_STABLE_S": "2",
                    "OJ_ESP_STEP": "1"}

    def package(self, name):
        p = os.path.join(self.t, "pkg", name + ".tgz")
        if not os.path.exists(p):
            d = os.path.join(self.t, "pkg", name); os.makedirs(os.path.join(d, "esp32"))
            with open(os.path.join(d, "esp32", "jooki_v2.bin"), "w") as f: f.write(name * 100)
            subprocess.run([BUSYBOX, "tar", "-czf", p, "-C", d, "esp32"], check=True)
        return p

    def sha(self, p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
    def path(self, n): return os.path.join(self.t, n)
    def write(self, n, s):
        with open(self.path(n), "w") as f: f.write(s)
    def read(self, n):
        try: return open(self.path(n)).read()
        except OSError: return ""
    def exists(self, n): return os.path.exists(self.path(n))
    def set(self, alive=None, wifi=None):
        if alive is not None: self.write("fw_version", "524\n" if alive else "0\n")
        if wifi is not None: self.write("route", ROUTE if wifi else ROUTE.split("\n")[0] + "\n")
    def flash(self, *words): self.write("flash", "\n".join(words) + "\n"); self.write("inst_n", "0")

    def run(self, *args, timeout=10):
        t0 = time.time()
        r = subprocess.run([BUSYBOX, "ash", self.script] + list(args), env=self.env, capture_output=True,
                           text=True, timeout=timeout)
        self.took = time.time() - t0
        return r

    def state(self): return self.read("data/openjooki/esp32/state").strip() or "none"
    def chip(self):
        c = self.read("chip").strip()
        return {self.sha(self.cand): "candidate", self.sha(self.package("stock")): "stock"}.get(c, c)
    def installs(self):
        names = {self.path("data/openjooki/esp32/candidate.tgz"): "candidate", self.path("data/openjooki/esp32/stock.tgz"): "stock-copy",
                 self.stock_etc: "stock-etc"}
        return [names.get(l, l) for l in self.read("inst.log").split()]
    def wait_state(self, *states, limit=12):
        end = time.time() + limit
        while time.time() < end and self.state() not in states: time.sleep(0.1)
        time.sleep(0.3)
        return self.state()
    def staged(self):
        r = self.run("install", self.cand)
        assert r.returncode == 0 and self.state() == "staged", (r.stdout, r.stderr)
    def done(self): shutil.rmtree(self.t, ignore_errors=True)


if not BUSYBOX:
    print("FAIL busybox is needed"); raise SystemExit(1)

# ------------------------------------------------------------------ nothing on trial
j = Jooki()
r = j.run("boot")
check("no trial: the start does nothing", r.returncode == 0 and j.installs() == [] and j.state() == "none" and j.chip() == "stock", r)
r = j.run("status")
check("no trial: status says so", "state: none" in r.stdout, r.stdout)
r = j.run("uninstall")
check("no trial: nothing to undo", "Nothing to undo" in r.stdout and j.state() == "none", r.stdout)
r = j.run("nonsense")
check("an unknown command: usage, nothing done", r.returncode == 2 and j.state() == "none", r)
j.done()

# ------------------------------------------------------------------ check (read-only)
j = Jooki()
r = j.run("check", j.cand)
check("check: a ready Jooki passes every line", r.returncode == 0 and "NOT OK" not in r.stdout and r.stdout.count("\nok") >= 9, r.stdout)
check("check: it writes nothing", j.state() == "none" and not j.exists("data/openjooki/esp32/candidate.tgz") and j.installs() == [], r)
r = j.run("check", j.package("other"))
check("check: another package is refused", r.returncode != 0 and "NOT OK  the new firmware package is not the expected one" in r.stdout, r.stdout)
r = j.run("check", j.path("nothing.tgz"))
check("check: a missing package is refused", r.returncode != 0, r.stdout)
j.done()
for label, kw, words in (("an unknown original firmware", {"stock_ok": False}, "original firmware package is missing"),
                         ("another chip API", {"api": "0x0205"}, "does not expect chip API"),
                         ("a chip not marked as loaded", {"loaded": False}, "not marked as loaded"),
                         ("a chip that does not answer", {"alive": False}, "chip does not answer"),
                         ("no Wi-Fi", {"wifi": False}, "no Wi-Fi now")):
    j = Jooki(**kw)
    r = j.run("check", j.cand)
    check("check: %s is refused" % label, r.returncode != 0 and words in r.stdout, r.stdout)
    before = j.chip()
    r = j.run("install", j.cand)
    check("install: %s, nothing changes" % label, r.returncode != 0 and j.state() == "none" and
          not j.exists("data/openjooki/esp32/candidate.tgz") and j.chip() == before and j.installs() == [], r.stdout)
    j.done()
j = Jooki(); j.write("free", "100")
r = j.run("install", j.cand)
check("install: not enough room on /data, nothing changes", r.returncode != 0 and "not enough room" in r.stdout and j.state() == "none", r.stdout)
j.done()

# ------------------------------------------------------------------ the good path
j = Jooki()
r = j.run("install", j.cand)
check("install: staged, both packages kept on /data, the chip untouched", r.returncode == 0 and j.state() == "staged"
      and j.sha(j.path("data/openjooki/esp32/candidate.tgz")) == j.sha(j.cand)
      and j.sha(j.path("data/openjooki/esp32/stock.tgz")) == j.sha(j.stock_etc) and j.installs() == [] and j.chip() == "stock", r.stdout)
check("install: says to restart", "Restart the Jooki" in r.stdout, r.stdout)
r = j.run("install", j.cand)
check("install twice: refused while one is staged", r.returncode != 0 and "trial is in progress" in r.stdout, r.stdout)
j.set(alive=False, wifi=False)            # the chip restarts on its new firmware
r = j.run("boot")
check("start: the new firmware is written, the start goes on at once", r.returncode == 0 and j.took < 1.5 and
      j.installs() == ["candidate"] and j.chip() == "candidate" and j.state() == "trying", (j.took, j.installs(), j.state()))
check("start: S55 is told to start the chip as after a factory write", not j.exists("data/mode/ESP32_FIRMWARE_LOADED"))
time.sleep(1); j.set(alive=True, wifi=True)
s = j.wait_state("accepted", "restore")
check("the chip answers and the Wi-Fi works, and still does later: accepted", s == "accepted" and not j.exists("rebooted"), s)
r = j.run("boot")
check("accepted: the next starts leave it alone", j.installs() == ["candidate"] and j.state() == "accepted" and j.chip() == "candidate")
check("the log tells the story", "accepted" in j.read("data/openjooki/esp32/log") and "accepted" in j.read("syslog"))
r = j.run("check", j.cand)
check("accepted: another trial may be checked", "no trial in progress (accepted)" in r.stdout, r.stdout)

# back to the original firmware, by hand
r = j.run("uninstall")
check("uninstall after acceptance: written back at the next start", j.state() == "restore" and "restart the Jooki" in r.stdout, r.stdout)
j.write("data/mode/ESP32_FIRMWARE_LOADED", "")
r = j.run("boot")
check("the next start writes the original firmware back from the copy on /data", j.installs() == ["candidate", "stock-copy"]
      and j.chip() == "stock" and j.state() == "restored" and not j.exists("data/mode/ESP32_FIRMWARE_LOADED"), (j.installs(), j.state()))
check("restored: no try counter left", not j.exists("data/openjooki/esp32/restore_tries"))
r = j.run("boot")
check("restored: the next starts leave it alone", j.installs() == ["candidate", "stock-copy"] and j.state() == "restored")
j.done()

# ------------------------------------------------------------------ the trial is not accepted
j = Jooki(); j.staged(); j.set(alive=True, wifi=False)
j.run("boot")
s = j.wait_state("restore", "accepted")
check("no Wi-Fi after the new firmware: back asked, and a restart", s == "restore" and j.exists("rebooted"), s)
check("the log says why", "no Wi-Fi within" in j.read("data/openjooki/esp32/log"), j.read("data/openjooki/esp32/log"))
j.run("boot")
check("the start after: the original firmware is written back", j.chip() == "stock" and j.state() == "restored", (j.chip(), j.state()))
j.done()

j = Jooki(); j.staged(); j.set(alive=False, wifi=False)
j.run("boot")
s = j.wait_state("restore", "accepted")
check("a chip that never answers: back too", s == "restore" and "the chip does not answer" in j.read("data/openjooki/esp32/log"), s)
j.done()

j = Jooki(); j.staged(); j.set(alive=True, wifi=True)
j.run("boot"); time.sleep(1.5); j.set(wifi=False)
s = j.wait_state("restore", "accepted")
check("a Wi-Fi that does not hold: back too", s == "restore" and j.exists("rebooted") and "did not hold" in j.read("data/openjooki/esp32/log"), s)
j.done()

j = Jooki(); j.staged(); j.set(alive=True, wifi=True)
j.run("boot")
j.run("uninstall")
time.sleep(4)
check("uninstall during the trial: the watch stands down, written back at the next start", j.state() == "restore" and not j.exists("rebooted"), j.state())
j.run("boot")
check("and it is", j.chip() == "stock" and j.state() == "restored")
j.done()

j = Jooki(); j.staged(); j.set(alive=False, wifi=False)
j.run("boot")
j.run("stock-back")
time.sleep(4)
check("S55 wrote the original back itself (API mismatch): restored, never accepted, no restart",
      j.state() == "restored" and not j.exists("rebooted"), j.state())
j.done()

# ------------------------------------------------------------------ restarts and failures
j = Jooki(); j.staged(); j.set(alive=False, wifi=False)
j.run("boot")
j.write("data/openjooki/esp32/state", "trying\n")   # the Jooki restarts before the verdict
j.run("boot")
check("a restart before the verdict: the original firmware is written back", j.installs() == ["candidate", "stock-copy"]
      and j.chip() == "stock" and j.state() == "restored", (j.installs(), j.state()))
j.done()

j = Jooki(); j.staged(); j.flash("die")
r = j.run("boot")
check("the Jooki stops in the middle of the write: the chip is half written", j.state() == "flashing" and j.chip() == "garbage", (j.state(), j.chip()))
j.run("boot")
check("the next start writes the original firmware back", j.chip() == "stock" and j.state() == "restored", (j.chip(), j.state()))
j.done()

j = Jooki(); j.staged(); j.flash("fail")
r = j.run("boot")
check("the write fails: the original firmware is written back in the same start",
      j.installs() == ["candidate", "stock-copy"] and j.chip() == "stock" and j.state() == "restored", (j.installs(), j.state()))
j.done()

j = Jooki(); j.staged(); j.flash("fail", "fail", "ok")
j.run("boot")
check("the write fails, then the first write back: the installer is tried a second time",
      j.installs() == ["candidate", "stock-copy", "stock-copy"] and j.chip() == "stock" and j.state() == "restored", (j.installs(), j.state()))
j.done()

j = Jooki(); j.staged(); j.flash(*["fail"] * 9)
j.run("boot")
check("the write back fails too: tried again at the next start, the chip back in normal mode",
      j.state() == "restoring" and j.read("data/openjooki/esp32/restore_tries").strip() == "1"
      and j.read("htdrv/esp_bootmode") == "0" and j.read("htdrv/esp_reset") == "1", (j.state(), j.read("htdrv/esp_bootmode")))
j.run("boot"); j.run("boot")
check("three starts without success: three tries", j.state() == "restoring"
      and j.read("data/openjooki/esp32/restore_tries").strip() == "3", j.state())
n = len(j.installs())
j.run("boot")
check("the fourth start gives up without writing", j.state() == "restore-failed" and len(j.installs()) == n
      and j.read("htdrv/esp_bootmode") == "0", (j.state(), j.installs()))
n = len(j.installs())
j.run("boot")
check("given up: no more writes", len(j.installs()) == n and j.state() == "restore-failed", j.installs())
r = j.run("uninstall")
check("given up: asking again starts over", j.state() == "restore", r.stdout)
j.flash("ok"); j.write("data/openjooki/esp32/restore_tries", "0"); j.run("boot")
check("and then works", j.chip() == "stock" and j.state() == "restored")
j.done()

j = Jooki(); j.staged()
j.write("data/openjooki/esp32/state", "trying\n")
j.write("data/openjooki/esp32/stock.tgz", "damaged")
j.run("boot")
check("a damaged copy: the original package of the system is used", j.installs() == ["stock-etc"] and j.chip() == "stock" and j.state() == "restored", j.installs())
j.done()

j = Jooki(); j.staged()
j.write("data/openjooki/esp32/state", "trying\n")
j.write("data/openjooki/esp32/stock.tgz", "damaged"); shutil.copy(j.package("other"), j.stock_etc)
j.run("boot")
check("no intact original anywhere: nothing written, said so", j.installs() == [] and j.state() == "restore-failed"
      and "no intact original" in j.read("data/openjooki/esp32/log"), (j.installs(), j.state()))
j.done()

j = Jooki(); j.staged()
j.write("data/openjooki/esp32/candidate.tgz", "damaged")
j.run("boot")
check("a damaged new package: nothing written at all", j.installs() == [] and j.chip() == "stock" and j.state() == "failed-damaged", j.state())
j.done()

j = Jooki(); j.staged()
r = j.run("uninstall")
check("uninstall before the start: cancelled, nothing written", j.state() == "none" and "Cancelled" in r.stdout
      and not j.exists("data/openjooki/esp32/candidate.tgz"), r.stdout)
j.run("boot")
check("and the start does nothing", j.installs() == [] and j.chip() == "stock")
j.done()

# ------------------------------------------------------------------ the start script and the real values
s55 = open(S55).read()
hook = s55.index("/jooki/bin/oj-esp32-trial boot")
check("S55: the trial runs after the factory write and before the logger and the driver",
      s55.index("  program_firmware\nfi\n") < hook < s55.index("\nstart_logger\n") < s55.index("modprobe ${ESP32_MODULE_NAME}\nfi"))
check("S55: an API mismatch rewrite is told to the trial", "oj-esp32-trial stock-back" in s55.split("esp32 driver mismatch")[1].split("elif")[0])
check("the script keeps the real paths and times outside the bench",
      all(x in SRC for x in ("OJ_ESP_WIFI_S:-600", "OJ_ESP_STABLE_S:-120", "/usr/bin/ml-esp32-install-firmware.sh",
                             "/etc/esp32/factory_default_firmware.tgz", "/sys/kernel/esp32sdio/fw_version", "/sys/kernel/htdrv")))
check("the pinned original is the one checked on the Jookis (firmware 0x020C)",
      STOCK == "7af7a71f682aa410a43fe2c091094380abd449cc33ef5eb4efe0ccd1e2ed8c53")
R.finish()
