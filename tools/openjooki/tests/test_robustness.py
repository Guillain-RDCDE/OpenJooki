"""A safer start, on the bench (real core): what keeps the Jooki alive when a piece fails.
  R1  no broker: the core waits its turns, it does not spin and burn the CPU (and the battery)
  R2  the broker killed: the core starts it again by itself (adapters.broker_watch), then reconnects
  R3  the maintenance SSH key: kept on /data (updates rewrite /home), only while the access is open
  R4  the page shows the key field while the access is open
R2 leaves a broker started from /etc/mosquitto: the end of the run (whatever happened before) puts the
bench broker and a plain core back for whatever runs next.
  python3 test_robustness.py"""
import os, shutil, subprocess, tempfile, time
import bench as B
from jk import PAGE
R = B.Results(lead=""); check = R.check
def sh(cmd): return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq7T1kq0rQw0Yl2m1nV4p9ZxKqvB0cVd7mH3sJk2LtR bench@openjooki"
KEYS, HOME_KEYS = "/data/openjooki/authorized_keys", "/home/root/.ssh/authorized_keys"
ETC_CONF = "/etc/mosquitto/mosquitto.conf"      # what the core's broker watch starts (the device's file)

B.setup()                                      # also: no key, no parent code left on /data
B.kill_brokers(); B.start_bench_broker()        # the bench broker (with its WebSocket), whatever ran before
B.run("./deploy_ui.sh")                         # before the core: it links the page's files at boot
# the broker watch is on on the device; on the bench only when asked: 3 s instead of 20
B.start_core(config=B.core_config({"broker_watch_s": 3}, "robustness"))
pid = B.core_pid()
made_conf, d = False, None
try:
    # --- R3 / R4 first, while the bench broker is up -------------------------------------------
    j = B.Jooki()
    maint = lambda: j.maint
    def last_error(): return (j.errors[-1] or {}).get("msg") if j.errors else None
    j.send("OJ_SSH_KEY", {"key": KEY})
    R.expect("R3 a key is refused while the maintenance access is closed", lambda: last_error() == "SSH_CLOSED" and not os.path.exists(KEYS), 5, lambda: (j.errors[-2:], os.path.exists(KEYS)))
    j.send("OJ_SSH_ON", {}); j.wait_state("maintenance.ssh", True)
    j.send("OJ_SSH_KEY", {"key": "ssh-rsa not-a-key; reboot"})
    R.expect("R3 something that is not a public key is refused", lambda: last_error() == "SSH_KEY_INVALID" and not os.path.exists(KEYS), 5, lambda: j.errors[-2:])
    j.send("OJ_SSH_KEY", {"key": "  " + KEY + "\n"}); j.poll(lambda: os.path.exists(KEYS) and maint().get("ssh_keys") == 1, 5)
    kept = open(KEYS).read() if os.path.exists(KEYS) else ""
    home = open(HOME_KEYS).read() if os.path.exists(HOME_KEYS) else ""
    check("R3 the key is kept on /data and put in place for dropbear", kept == KEY + "\n" and home == kept and maint().get("ssh_keys") == 1, (kept, home, maint()))
    mode = oct(os.stat(KEYS).st_mode & 0o777) if os.path.exists(KEYS) else None
    check("R3 ... readable by root only", mode == "0o600", mode)
    j.send("OJ_SSH_KEY", {"key": KEY}); j.barrier()        # the file is written in the handler, before our state comes back
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
            j.send("OJ_SSH_KEY", {"clear": True}); j.poll(lambda: maint().get("ssh_keys") == 0, 5)
            check("R3 'forget the keys' removes both files", not os.path.exists(KEYS) and not os.path.exists(HOME_KEYS), (os.path.exists(KEYS), os.path.exists(HOME_KEYS)))
            j.send("OJ_SSH_OFF", {}); j.poll(lambda: maint().get("ssh") is False, 5)
            try: pg.wait_for_function("!document.querySelector('[data-k=sshkey]')", timeout=5000)
            except Exception: pass
            check("R4 ... and hides it once the access is closed", pg.locator("[data-k=sshkey]").count() == 0)
            b.close()
    except ImportError:
        print("SKIP R4 (no playwright)")
    j.close()

    # --- R1: no broker, no spinning ------------------------------------------------------------
    mark = B.log_mark()
    B.kill_brokers()
    B.wait_log("bus.down", mark, 5)        # the core noticed; the watch acts 3 s after that
    t0, c0 = time.time(), B.cpu_ticks(pid)
    B.quiet(1.0, "CPU use is measured over one second of waiting for a broker, within the 3 s before the watch acts")
    used = (B.cpu_ticks(pid) - c0) / os.sysconf("SC_CLK_TCK") / (time.time() - t0)
    check("R1 without a broker the core does not spin (CPU %.0f %%)" % (used * 100), used < 0.2, used)

    # --- R2: the broker comes back by itself ---------------------------------------------------
    if not os.path.exists(ETC_CONF):
        os.makedirs("/etc/mosquitto", exist_ok=True)
        open(ETC_CONF, "w").write("listener 1883 127.0.0.1\nallow_anonymous true\n"); made_conf = True
    started = B.poll(lambda: "mosquitto -c " + ETC_CONF in sh("ps -eo args"), 20, every=0.5)
    check("R2 the core started the broker again by itself", started, sh("ps -eo args | grep -i mosq"))
    # the core reconnects on its own backoff (a few seconds): ask until it answers
    t0 = time.time()
    def jooki_ok():
        try: j2 = B.Jooki(timeout=2); j2.close(); return True
        except (B.WaitTimeout, OSError) as e: print("  connect:", str(e)[:80]); return False
    back = B.poll(jooki_ok, 30, every=1)
    check("R2 ... and everything talks again (the page gets its state, after %.0f s)" % (time.time() - t0), back)
    check("R1 the core is still the same process", B.core_pid() == pid, (pid, B.core_pid()))

    # --- R5: the boot loop runs our start scripts, never the originals kept next to them ----------
    d = tempfile.mkdtemp()
    os.makedirs(d + "/rcS.d"); os.makedirs(d + "/rc5.d")
    for n in ("S55_ml-start-wifi.sh", "S58_mosquitto.sh"):
        open(d + "/rcS.d/" + n, "w").write("echo RAN %s\n" % n)
        open(d + "/rcS.d/" + n + ".openjooki-orig", "w").write("#!/bin/sh\necho RAN-ORIGINAL %s\n" % n)
        os.chmod(d + "/rcS.d/" + n + ".openjooki-orig", 0o755)
    rcs = open(os.path.join(B.HERE, "..", "system", "rcS")).read().replace("\r", "")
    open(d + "/rcS", "w").write(rcs.replace("/etc/rcS.d", d + "/rcS.d").replace("/etc/rc5.d", d + "/rc5.d").replace("/dev/kmsg", d + "/kmsg-none"))
    ran = sh("sh %s/rcS" % d)
    check("R5 the boot loop runs the new start scripts", "RAN S55_ml-start-wifi.sh" in ran and "RAN S58_mosquitto.sh" in ran, ran)
    check("R5 ... and never the originals kept next to them", "RAN-ORIGINAL" not in ran, ran)
finally:
    # back to the bench broker and a plain core for whatever runs next; our own files gone
    B.kill_brokers()
    B.start_bench_broker()
    B.start_core()
    if made_conf: os.remove(ETC_CONF)
    if d: shutil.rmtree(d, ignore_errors=True)
R.finish()
