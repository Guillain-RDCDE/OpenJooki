#!/usr/bin/env python3
"""ADR-0011: player.lib is a loader that reads the real core from /jooki/lib/core.lua and runs it.

This proves the device boot path the bench's own harness does not exercise (the harness loads
build/core.lua directly). It runs the loader under a host simulator that provides the C host's four
functions, and checks the core boots to READY. It also checks the loader's guards: a truncated core
file and a missing core file are refused, never run.

  CORE_BUILD=<repo>/build python3 test_loader.py      (defaults to ../../../build)
"""
import os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BUILD = os.environ.get("CORE_BUILD", os.path.join(REPO, "build"))
sys.path.insert(0, os.path.join(REPO, "tools", "openjooki"))
import lua_patches as L  # noqa: E402

CORE_PATH = "/jooki/lib/core.lua"   # the loader's hard-coded location (matches the device)

HOSTSIM = r"""
function c_syslog(level, msg) io.stderr:write("SYSLOG "..tostring(level).." "..tostring(msg).."\n") end
function c_alsa_set_volume(v, x) return 0 end
function c_isTerminating() return _G.__terminating == true end
function c_sd_notify() io.stdout:write("READY\n"); io.stdout:flush(); _G.__terminating = true end
local src = assert(io.open(arg[1])):read('*a')
local fn = assert(loadstring(src, '=player.lib'))
local ok, err = pcall(fn)
if not ok then io.stderr:write("LOADER_ERROR "..tostring(err).."\n") end
"""


def run(loader_path, seconds=8):
    env = dict(os.environ, OPENJOOKI_LOG="info",
               id="bench", hostname="jooki-bench.local", ip="10.0.0.2",
               wifi_mac="00:11:22:33:44:55", machine="ml-j2000", firmware="bench")
    p = subprocess.run(["lua5.1", HOSTSIM_FILE, loader_path],
                       capture_output=True, text=True, timeout=seconds + 5, env=env)
    return p.stdout, p.stderr


def main():
    lib = open(os.path.join(BUILD, "player.lib"), "rb").read()
    src = L.decode(lib)
    assert "_OPENJOOKI_LOADER" in src[:400], "player.lib is not a loader (ADR-0011)"
    core = open(os.path.join(BUILD, "core.min.lua"), "rb").read()
    import re
    m = re.search(r"local EXPECT=(\d+)", src)
    assert m and int(m.group(1)) == len(core), \
        "loader EXPECT %s != core.min.lua %d" % (m and m.group(1), len(core))
    print("[loader] player.lib is a loader, EXPECT matches core.min.lua (%d B)" % len(core))

    global HOSTSIM_FILE
    tmp = tempfile.mkdtemp(prefix="ojloader-")
    HOSTSIM_FILE = os.path.join(tmp, "hostsim.lua")
    open(HOSTSIM_FILE, "w", newline="\n").write(HOSTSIM)
    loader = os.path.join(tmp, "loader.lua")
    open(loader, "w", newline="\n").write(src)

    os.makedirs(os.path.dirname(CORE_PATH), exist_ok=True)

    # 1) the good case: the loader boots the core to READY
    open(CORE_PATH, "wb").write(core)
    # the loop runs forever; the timeout kills it, READY comes first
    p = subprocess.Popen(["lua5.1", HOSTSIM_FILE, loader],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=dict(os.environ, OPENJOOKI_LOG="info", id="bench",
                                  hostname="jooki-bench.local", ip="10.0.0.2",
                                  wifi_mac="00:11:22:33:44:55", machine="ml-j2000", firmware="bench"))
    ready = False
    t0 = time.time()
    try:
        while time.time() - t0 < 10:
            line = p.stdout.readline()
            if not line:
                break
            if "READY" in line:
                ready = True
                break
    finally:
        p.terminate()
        try: p.wait(timeout=3)
        except Exception: p.kill()
    assert ready, "the loader did not boot the core to READY"
    print("[loader] boots the core to READY")

    # 2) a truncated core file is refused, never run
    open(CORE_PATH, "wb").write(core[:-1])
    out, err = run(loader, seconds=4)
    assert "READY" not in out, "a truncated core must not boot"
    assert "core size" in err, "the loader must report the wrong size: %s" % err[-300:]
    print("[loader] refuses a core of the wrong size")

    # 3) a missing core file is refused
    os.remove(CORE_PATH)
    out, err = run(loader, seconds=4)
    assert "READY" not in out, "a missing core must not boot"
    assert "core file not found" in err, "the loader must report the missing file: %s" % err[-300:]
    print("[loader] refuses a missing core file")

    # leave the good core in place for anything that follows
    open(CORE_PATH, "wb").write(core)
    print("OK: loader boot path (ADR-0011) verified (boot + 2 guards)")


if __name__ == "__main__":
    main()
