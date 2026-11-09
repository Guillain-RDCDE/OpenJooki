#!/usr/bin/env python3
"""The guard (system/oj-guard.sh, S95): a system that starts but whose core does not goes back by itself.

The real script runs under busybox ash; curl, the bootloader tools, mount and reboot are small
stand-ins on its PATH, each writing down what it was asked. The times are shortened.
  python3 test_guard.py
"""
import os, shutil, stat, subprocess, tempfile, time
import bench as B

R = B.Results(); check = R.check
SCRIPT = os.path.join(B.REPO, "tools", "openjooki", "system", "oj-guard.sh")
BUSYBOX = shutil.which("busybox")
TOOLS = {
    # the page: answers as `page_script` says, one line per try; the last line repeats
    "curl": 'n=$(cat "$T/curl_n" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$T/curl_n"\n'
            'l=$(sed -n "${n}p" "$T/page"); [ -n "$l" ] || l=$(tail -n 1 "$T/page"); [ "$l" = ok ]\n',
    "fw_printenv": 'cat "$T/env_$1" 2>/dev/null | sed "s/^/$1=/"\n',
    "fw_setenv": '[ -e "$T/setenv_fails" ] && exit 1\n'
                 'while read k v; do echo "$v" > "$T/env_$k"; echo "$k $v" >> "$T/setenv.log"; done < "$2"\n',
    "mount": '[ -e "$T/mount_fails" ] && exit 1\nmkdir -p "$4/boot" "$4/jooki/lib" "$4/jooki/bin"\n'
             'if [ ! -e "$T/incomplete" ]; then touch "$4/boot/uImage" "$4/jooki/lib/player.lib" "$4/jooki/bin/player"; fi\n'
             'echo "$2 $3" >> "$T/mount.log"\n',
    "umount": 'rm -rf "$1"; mkdir -p "$1"\n',
    "reboot": 'date +%s > "$T/rebooted"\n',
    "logger": 'echo "$*" >> "$T/log"\n',
    "sync": ':\n',
}


def run(part="2", page=("no",), mark=None, files=(), limit=1):
    t = tempfile.mkdtemp(prefix="oj-guard-")
    tools = os.path.join(t, "bin"); os.mkdir(tools)
    for name, body in TOOLS.items():
        p = os.path.join(tools, name)
        with open(p, "w") as f: f.write("#!%s ash\nT=%s\n%s" % (BUSYBOX, t, body))
        os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
    for applet in ("sed", "cat", "tail", "sleep", "mkdir", "rm", "date", "touch"):
        os.symlink(BUSYBOX, os.path.join(tools, applet))
    with open(os.path.join(t, "page"), "w") as f: f.write("\n".join(page) + "\n")
    with open(os.path.join(t, "env_mender_boot_part"), "w") as f: f.write(part + "\n")
    os.makedirs(os.path.join(t, "data", "openjooki")); os.makedirs(os.path.join(t, "data", "mode"))
    if mark:
        with open(os.path.join(t, "data", "openjooki", "guard_fled"), "w") as f: f.write(mark + "\n")
    for n in files:
        p = os.path.join(t, n); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").close()
    env = {"OJ_GUARD_PATH": tools, "OJ_GUARD_LIMIT": str(limit), "OJ_GUARD_STEP": "1", "OJ_GUARD_SECOND": "1",
           "OJ_GUARD_DATA": os.path.join(t, "data"), "OJ_GUARD_MNT": os.path.join(t, "mnt"),
           "OJ_GUARD_URL": "http://127.0.0.1/", "OJ_GUARD_PART": "/dev/card-p"}
    # rcS sources it: it must hand back at once, whatever happens next
    t0 = time.time()
    subprocess.run([BUSYBOX, "ash", SCRIPT], env=env, timeout=5, check=True)
    t1 = time.time() - t0
    # the background part ends by itself; wait for its last move
    for _ in range(100):
        if subprocess.run(["pgrep", "-f", "oj-guard-.*"], capture_output=True).returncode != 0 and False: break
        if os.path.exists(os.path.join(t, "rebooted")): break
        log = os.path.join(t, "log")
        if os.path.exists(log) and any(w in open(log).read() for w in ("answers", "staying", "nothing to do")): break
        if files and "data/mode/NO_APP" in files and _ >= 30: break
        time.sleep(0.1)
    time.sleep(0.2)
    def read(n):
        try: return open(os.path.join(t, n)).read()
        except OSError: return ""
    res = {"handback": t1, "rebooted": os.path.exists(os.path.join(t, "rebooted")), "setenv": read("setenv.log"),
           "mark": read("data/openjooki/guard_fled").strip(), "log": read("log"), "part": read("env_mender_boot_part").strip(),
           "mount": read("mount.log"), "curl_n": read("curl_n").strip()}
    shutil.rmtree(t, ignore_errors=True)
    return res


if not BUSYBOX:
    print("FAIL busybox is needed"); raise SystemExit(1)

r = run(page=("ok",))
check("a core that answers: it hands back at once", r["handback"] < 1, r)
check("a core that answers: nothing changes", not r["rebooted"] and not r["setenv"] and r["part"] == "2", r)

r = run(page=("no", "no", "ok"), limit=5)
check("a core that takes its time: nothing changes", not r["rebooted"] and not r["setenv"], r)

r = run(page=("no",))
check("no page: back to the other partition, and a restart", r["rebooted"] and r["part"] == "3", r)
check("no page: all four settings", r["setenv"].split("\n")[:4] == ["mender_boot_part 3", "mender_boot_part_hex 3", "upgrade_available 0", "bootcount 0"], r["setenv"])
check("no page: the other partition is looked at read-only", "/dev/card-p3" in r["mount"] and "ro" in r["mount"], r["mount"])
check("no page: it remembers what it fled", r["mark"] == "2", r)

r = run(part="3", page=("no",))
check("from partition 3 too", r["rebooted"] and r["part"] == "2" and r["mark"] == "3", r)

r = run(page=("ok", "no"), limit=2)
check("a core that answers once and dies: back too", r["rebooted"] and r["part"] == "3", r)

r = run(part="3", page=("no",), mark="2")
check("both bad: never back to the partition just fled, no restart loop", not r["rebooted"] and not r["setenv"] and r["part"] == "3", r)

r = run(part="2", page=("no",), mark="2")
check("an old mark about this very partition does not stop it", r["rebooted"] and r["part"] == "3", r)

r = run(part="2", page=("ok",), mark="3")
check("a healthy core forgets the mark", r["mark"] == "" and not r["rebooted"], r)

r = run(page=("no",), files=("incomplete",))
check("an incomplete other partition: stays", not r["rebooted"] and not r["setenv"] and r["part"] == "2", r)

r = run(page=("no",), files=("mount_fails",))
check("another partition that will not mount: stays", not r["rebooted"] and not r["setenv"], r)

r = run(page=("no",), files=("setenv_fails",))
check("settings that cannot be written: no restart, no mark", not r["rebooted"] and r["mark"] == "", r)

r = run(part="1", page=("no",))
check("the factory partition: not its business", not r["rebooted"] and not r["setenv"] and r["part"] == "1", r)

r = run(page=("no",), files=("data/mode/NO_APP",))
check("NO_APP (the app is off on purpose): nothing", not r["rebooted"] and not r["setenv"], r)

src = open(SCRIPT).read()
check("the script keeps the real times outside the bench", "OJ_GUARD_LIMIT:-300" in src and "/dev/mmcblk0p" in src)
R.finish()
