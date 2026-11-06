#!/usr/bin/env python3
"""The network MQTT switch ("Home automation") never leaves the Jooki deaf (#28).

Turning it on or off, and the core setting it up again once the Wi-Fi has an address (at every
start since 2.4.18), runs the device's S57_oj-security.sh, which restarts the broker. The Jooki's
closed hardware controllers (tokens and knobs, buttons, lights) leave with exit 0 when the broker
goes, and their launcher only restarts a crash: in 2.4.18 they stayed gone, no token, no heart
button, until the next restart. Here the REAL script runs under busybox ash (busybox first on the
PATH: ps, pidof, as on the device), its paths moved into a sandbox, against a real mosquitto, with
three stand-in controllers built from fake_ctrl.c and a launcher with the same rule as the
device's (start again after a crash, stop after exit 0 or a kill):

  - at boot (switch on, no address yet): no network listener; once the address comes, the broker
    is restarted with it and the three controllers are back on the bus, once each;
  - the listener: the per-Jooki password is accepted, anonymous and a wrong password refused;
    localhost stays anonymous (the controllers' and the core's side);
  - the same settings again: nothing restarted; off: no listener, controllers back;
  - 20 changes in a row, and a controller that had just crashed: never deaf, never doubled.

  sudo python3 test_mqtt_lan.py        (root; busybox, mosquitto, gcc; no core needed)
"""
import os, shutil, socket, struct, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
SYSTEM = os.path.join(HERE, "..", "system")
PORT, WS_PORT = 18830, 18800          # beside the bench's own broker (1883, 8000)
CTRL = ("gpio_ctrl", "ht_ctrl", "esp32_ctrl")
RESULTS = []


def check(name, ok, info=""):
    RESULTS.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  -> " + str(info)[:300]), flush=True)


def need(tool):
    if not shutil.which(tool):
        print("FAIL %s is needed" % tool); sys.exit(1)


for t in ("busybox", "mosquitto", "mosquitto_passwd", "gcc"):
    need(t)
S = tempfile.mkdtemp(prefix="oj-mqttlan-")
os.chmod(S, 0o755)                     # the broker drops to its own user and reads the password file here
LAN_IP = None


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1)); return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def setup():
    global LAN_IP
    for d in ("data", "etc", "www", "bin", "jbin", "bb"):
        os.makedirs(os.path.join(S, d))
    for a in ("ps", "pidof", "awk", "grep", "head", "cut", "sleep", "cmp", "logger", "kill", "mv", "cp", "chmod",
              "chown", "rm", "mkdir", "dd", "md5sum", "printf", "touch", "cat", "tr"):
        os.symlink(shutil.which("busybox"), os.path.join(S, "bb", a))
    first = os.path.join(S, "jbin", CTRL[0])
    subprocess.run(["gcc", "-O", "-o", first, os.path.join(HERE, "fake_ctrl.c")], check=True)
    for c in CTRL[1:]:
        shutil.copy(first, os.path.join(S, "jbin", c))
    with open(os.path.join(S, "jbin", "ml-launch-controller.sh"), "w") as f:
        f.write("#!/bin/sh\n# the device launcher's rule: again after a crash, never after exit 0 or a kill\n"
                "while :; do \"$1\" %d; rc=$?; [ $rc -gt 0 ] || break; [ $rc -eq 143 -o $rc -eq 137 ] && break; sleep 1; done\n" % PORT)
    os.chmod(os.path.join(S, "jbin", "ml-launch-controller.sh"), 0o755)
    LAN_IP = lan_ip()
    with open(os.path.join(SYSTEM, "mosquitto.conf")) as f:
        conf = f.read()
    conf = conf.replace("\nport 1883", "\nport %d" % PORT).replace("\nlistener 8000", "\nlistener %d" % WS_PORT)
    conf = conf.replace("/etc/mosquitto/passwd", S + "/etc/passwd")
    with open(os.path.join(S, "etc", "mosquitto.conf"), "w") as f:
        f.write(conf)
    with open(os.path.join(SYSTEM, "oj-security.sh")) as f:
        sec = f.read()
    for old, new in (("/data/openjooki", S + "/data"), ("/etc/mosquitto/mosquitto.conf", S + "/etc/mosquitto.conf"),
                     ("/etc/mosquitto/passwd", S + "/etc/passwd"), ("/jooki/app/www/public/oj-auth.json", S + "/www/oj-auth.json"),
                     ("listener 1883 ", "listener %d " % PORT), ("/sbin/ip route get 1", S + "/bin/ip"),
                     ("/usr/sbin/mosquitto -c", "mosquitto -c"), ("grep '[m]osquitto -c'", "grep '[m]osquitto -c %s'" % S),
                     ("/jooki/bin", S + "/jbin"), ("/var/run/mosquitto.pid", S + "/mosquitto.pid")):
        if old not in sec:
            print("FAIL the script changed: %r not found, update this test" % old); sys.exit(1)
        sec = sec.replace(old, new)
    with open(os.path.join(S, "sec.sh"), "w") as f:
        f.write(sec)
    # `ip route get 1`: an answer with our address once "online"
    with open(os.path.join(S, "bin", "ip"), "w") as f:
        f.write('#!/bin/sh\n[ -f %s/online ] && echo "1.0.0.0 via 1.1.1.1 dev eth0 src %s uid 0"\n' % (S, LAN_IP))
    os.chmod(os.path.join(S, "bin", "ip"), 0o755)


ENV = dict(os.environ, PATH=S + "/bb:/usr/sbin:/usr/bin:/sbin:/bin")


def sh(cmd):
    return subprocess.run(["busybox", "ash", "-c", cmd], capture_output=True, text=True, env=ENV, timeout=120).stdout.strip()


def sec():
    subprocess.run(["busybox", "ash", os.path.join(S, "sec.sh")], capture_output=True, env=ENV, timeout=120)


def flag(on):
    p = os.path.join(S, "data", "mqtt_lan")
    if on:
        open(p, "a").close()
    elif os.path.exists(p):
        os.remove(p)


def broker():
    return sh("ps | grep '[m]osquitto -c %s' | awk '{print $1}' | head -n 1" % S)


def pids(c):
    return sh("pidof %s" % c).split()


# ------------------------------------------------------------------ a tiny MQTT 3.1.1 client
def _s(x):
    x = x.encode(); return struct.pack(">H", len(x)) + x


def _len(n):
    o = b""
    while True:
        d, n = n % 128, n // 128
        o += bytes([d | (128 if n else 0)])
        if not n: return o


def mqtt_connect(host, user=None, pw=None):
    """the CONNACK code, or None when nothing listens there"""
    flags = 2 | (0xC0 if user else 0)
    body = _s("MQTT") + bytes([4, flags, 0, 30]) + _s("probe%d" % time.time_ns())
    if user: body += _s(user) + _s(pw)
    try:
        c = socket.create_connection((host, PORT), 4)
    except OSError:
        return None, None
    c.send(bytes([0x10]) + _len(len(body)) + body)
    c.settimeout(4)
    try:
        r = c.recv(4)
    except OSError:
        r = b""
    if len(r) < 4:
        c.close(); return -1, None
    return r[3], c


def alive():
    """{controller: pid} said on the bus (the retained alive messages)"""
    rc, c = mqtt_connect("127.0.0.1")
    if rc != 0:
        return {}
    sub = struct.pack(">H", 1) + _s("/j/fake/alive/#") + b"\x00"
    c.send(bytes([0x82]) + _len(len(sub)) + sub)
    c.settimeout(1.0); buf = b""
    try:
        while True:
            d = c.recv(4096)
            if not d: break
            buf += d
    except OSError:
        pass
    c.close()
    out, i = {}, 0
    while i < len(buf):
        t, m, k, j = buf[i], 0, 1, i + 1
        while True:
            m += (buf[j] & 127) * k; k *= 128; j += 1
            if not buf[j - 1] & 128: break
        p = buf[j:j + m]
        if t >> 4 == 3:
            tl = struct.unpack(">H", p[:2])[0]
            out[p[2:2 + tl].decode().split("/")[-1]] = p[2 + tl:].decode()
        i = j + m
    return out


def lan(user=None, pw=None):
    rc, c = mqtt_connect(LAN_IP, user, pw)
    if c: c.close()
    return rc


def all_back(label):
    """each controller running once, and on the bus with that very process"""
    a = alive(); p = {c: pids(c) for c in CTRL}
    ok = all(len(p[c]) == 1 and a.get(c) == p[c][0] for c in CTRL)
    check(label, ok, "running %s, on the bus %s" % (p, a))


def stop_all():
    subprocess.run(["pkill", "-f", S + "/"], capture_output=True)
    subprocess.run(["pkill", "-f", "mosquitto -c " + S], capture_output=True)


def main():
    setup()
    if not LAN_IP:
        print("FAIL no network address on this machine"); sys.exit(1)
    try:
        # boot: S57 (switch on, no address yet), S58 the broker, then ml-start-app.sh's controllers
        flag(True); sec()
        subprocess.run(["chown", "mosquitto", os.path.join(S, "etc", "passwd")], capture_output=True)
        subprocess.run(["mosquitto", "-c", os.path.join(S, "etc", "mosquitto.conf"), "-d"], check=True)
        time.sleep(1)
        for c, nice in zip(CTRL, ("-5", "-1", "-5")):
            subprocess.Popen([os.path.join(S, "jbin", "ml-launch-controller.sh"), os.path.join(S, "jbin", c), nice],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(1.5)
        with open(os.path.join(S, "data", "ws_secret")) as f:
            pw = f.readline().strip()
        b0 = broker()
        all_back("boot: the three controllers on the bus")
        check("boot: no network listener before the Wi-Fi has an address", lan("jooki", pw) is None)

        # the address comes: the core asks for the listener (shell action mqtt_lan, on)
        open(os.path.join(S, "online"), "w").close()
        t = time.time(); sec(); took = time.time() - t
        time.sleep(1)
        b1 = broker()
        check("address: the broker restarted with the listener", b1 and b1 != b0, (b0, b1))
        all_back("address: the three controllers back on the bus, once each (#28)")
        check("address: the script is quick (%.1f s)" % took, took < 15, took)
        check("network: the Jooki's password is accepted", lan("jooki", pw) == 0)
        check("network: anonymous refused", lan() != 0)
        check("network: a wrong password refused", lan("jooki", "nope") != 0)
        check("localhost: still anonymous", mqtt_connect("127.0.0.1")[0] == 0)

        # the same settings again: nothing to restart
        before = {c: pids(c) for c in CTRL}
        sec(); time.sleep(1)
        check("same settings: the broker kept", broker() == b1, (b1, broker()))
        check("same settings: the controllers kept", {c: pids(c) for c in CTRL} == before)

        # off
        flag(False); sec(); time.sleep(1)
        b3 = broker()
        check("off: the broker restarted", b3 and b3 != b1, (b1, b3))
        all_back("off: the three controllers back on the bus, once each")
        check("off: no network listener", lan("jooki", pw) is None)

        # 20 changes in a row, as fast as the script goes
        for i in range(20):
            flag(i % 2 == 0); sec()
        time.sleep(2)
        all_back("20 changes in a row: never deaf, never doubled")
        check("20 changes: the listener is off (the last was off)", lan("jooki", pw) is None)

        # a controller that crashed on its own just before (its launcher waits 1 s to start it again)
        esp = pids("esp32_ctrl")
        if esp:
            sh("kill -SEGV %s" % esp[0])
        flag(True); sec(); time.sleep(2)
        all_back("a controller crashed just before: not doubled, back on the bus")
        check("on again: the listener answers", lan("jooki", pw) == 0)
        n = sum(1 for p in os.listdir("/proc") if p.isdigit() and _is_launcher(p))
        check("one launcher per controller (%d)" % n, n == 3, n)
    finally:
        stop_all()
        shutil.rmtree(S, ignore_errors=True)
    bad = RESULTS.count(False)
    print("\n%d/%d passed" % (len(RESULTS) - bad, len(RESULTS)), flush=True)
    sys.exit(1 if bad else 0)


def _is_launcher(pid):
    try:
        with open("/proc/%s/cmdline" % pid, "rb") as f:
            cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return False
    # the launcher's loop runs in a subshell of the script: count the scripts, not their subshells
    return "ml-launch-controller.sh %s/jbin/" % S in cmd and _parent_is_not_launcher(pid)


def _parent_is_not_launcher(pid):
    try:
        with open("/proc/%s/stat" % pid) as f:
            ppid = f.read().rsplit(")", 1)[1].split()[1]
        with open("/proc/%s/cmdline" % ppid, "rb") as f:
            return b"ml-launch-controller.sh" not in f.read()
    except (OSError, IndexError):
        return True


if __name__ == "__main__":
    main()
