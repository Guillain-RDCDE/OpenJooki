#!/usr/bin/env python3
"""OpenJooki — add the new web page + application fixes to a firmware image.

Takes an OpenJooki firmware image (ext4 rootfs, .img or .img.gz), applies exactly
what `jooki.py patch webui` applies on a live Jooki, and writes a new image:

  * /jooki/lib/player.lib            -> patched (tools/openjooki/lua_patches.py);
                                        the original is kept as player.lib.openjooki-orig
  * /jooki/app/www/public/           -> the new web page (tools/openjooki/webui/);
                                        the 2018 web app is moved to public-openjooki-orig/
  * /etc/syslog-ng/syslog-ng.conf    -> logs stay on the Jooki (tools/openjooki/system/);
                                        the original is kept as <file>.openjooki-orig
  * /etc/openjooki-version           -> the new version number
  * /etc/hostname, /etc/mac          -> neutral (each Jooki writes its own at every boot)
  * the leftovers of the Jooki the base image was dumped from are removed (/start, /tmp/*,
    stray files, authorized SSH keys) and the free blocks zeroed (tools/sdcard/make_card_image.py,
    scrub_rootfs); --forget <string> makes the build fail if that string is still anywhere

No mount and no root needed: it edits the ext4 image with `debugfs` (e2fsprogs),
then checks it with `e2fsck -fn` and reads every written file back.

Usage: add-webui-to-image.py <in.img[.gz]> <out.img> <version> [--core build/player.lib] [--forget <s>]...
       --core: install the 2.0 core (tools/build/bundle.py) instead of the patched program
Then:  scripts/make-release.sh <out.img> <version>
"""
import gzip, hashlib, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "tools", "openjooki")
sys.path.insert(0, TOOL)
sys.path.insert(0, os.path.join(HERE, "..", "tools", "sdcard"))
import lua_patches as L  # noqa: E402
from jooki import SYSTEM_DIR, WEBUI_FILES, WEBUI_DIRS, webui_dir_files, file_mode, load_core, core_side_files, system_files  # noqa: E402
from make_card_image import scrub_rootfs  # noqa: E402

WEBUI = os.path.join(TOOL, "webui")
WEB_FILES = WEBUI_FILES   # one list, in jooki.py
PUB = "/jooki/app/www/public"
ORIG = "/jooki/app/www/public-openjooki-orig"
OLD_FILES = ("index.html", "asset-manifest.json", "service-worker.js", "deezer_channel.html",
             "static/js/main.e47a9287.js", "static/css/main.b3f3345f.css")
LIB = "/jooki/lib/player.lib"


def dbg(img, cmds, write=False):
    """Run debugfs commands; return stdout. Raises on reported errors."""
    with tempfile.NamedTemporaryFile("w", suffix=".cmd", delete=False) as f:
        f.write("\n".join(cmds) + "\n")
        path = f.name
    try:
        r = subprocess.run(["debugfs"] + (["-w"] if write else []) + ["-f", path, img],
                           capture_output=True, text=True)
    finally:
        os.unlink(path)
    bad = [l for l in r.stderr.splitlines() if l.strip() and not l.startswith("debugfs ")
           and "Allocated inode" not in l]
    if write and bad:
        raise RuntimeError("debugfs: " + " | ".join(bad))
    return r.stdout


def cat(img, path):
    r = subprocess.run(["debugfs", "-R", "cat " + path, img], capture_output=True)
    return r.stdout


def exists(img, path):
    r = subprocess.run(["debugfs", "-R", "stat " + path, img], capture_output=True, text=True)
    return "Inode:" in r.stdout


def put(img, local, path, mode="0100644"):
    cmds = []
    if exists(img, path):
        cmds.append("rm " + path)
    cmds += ["write %s %s" % (local, path),
             "set_inode_field %s mode %s" % (path, mode),
             "set_inode_field %s uid 0" % path,
             "set_inode_field %s gid 0" % path]
    dbg(img, cmds, write=True)


def put_dir(img, local_dir, names, path):
    """A folder of many small files (the token pictures): replaced whole, in one debugfs run."""
    if exists(img, path):
        out = subprocess.run(["debugfs", "-R", "ls -p " + path, img], capture_output=True, text=True).stdout
        old = [l.split("/")[5] for l in out.splitlines() if l.count("/") >= 6 and l.split("/")[5] not in (".", "..")]
        dbg(img, ["rm %s/%s" % (path, n) for n in old] + ["rmdir " + path], write=True)
    cmds = ["mkdir " + path, "set_inode_field %s uid 0" % path, "set_inode_field %s gid 0" % path]
    for n in names:
        p = path + "/" + n
        cmds += ["write %s %s" % (os.path.join(local_dir, n), p), "set_inode_field %s mode 0100644" % p,
                 "set_inode_field %s uid 0" % p, "set_inode_field %s gid 0" % p]
    dbg(img, cmds, write=True)


def main():
    argv = sys.argv[1:]
    core = None
    if "--core" in argv:
        i = argv.index("--core"); core = argv[i + 1]; del argv[i:i + 2]
    forget = []
    while "--forget" in argv:
        i = argv.index("--forget"); forget.append(argv[i + 1]); del argv[i:i + 2]
    if len(argv) != 3:
        print(__doc__); sys.exit(1)
    src, out, version = argv
    work = tempfile.mkdtemp(prefix="ojimg-")
    print("copying image…")
    if src.endswith(".gz"):
        with gzip.open(src, "rb") as fi, open(out, "wb") as fo:
            shutil.copyfileobj(fi, fo, 1 << 20)
    else:
        shutil.copyfile(src, out)

    # --- application fixes (player.lib) ---
    base = cat(out, LIB + ".openjooki-orig") if exists(out, LIB + ".openjooki-orig") else cat(out, LIB)
    source = L.decode(base)
    if L.is_patched(source):
        raise SystemExit("the image's player.lib is already patched and has no original copy")
    lib = load_core(core) if core else L.encode(L.apply(source))
    open(os.path.join(work, "orig.lib"), "wb").write(base)
    open(os.path.join(work, "player.lib"), "wb").write(lib)
    if not exists(out, LIB + ".openjooki-orig"):
        put(out, os.path.join(work, "orig.lib"), LIB + ".openjooki-orig")
    put(out, os.path.join(work, "player.lib"), LIB)
    print("player.lib: 2.0 core %s (%d B)" % (core, len(lib)) if core else "player.lib patched (%d fixes)" % len(L.P))
    # the real core next to the loader (ADR-0011): /jooki/lib/core.lua
    side = core_side_files(core) if core else {}
    for path, data in sorted(side.items()):
        local = os.path.join(work, os.path.basename(path))
        open(local, "wb").write(data)
        put(out, local, path, mode="0100" + file_mode(path))
        print("core file installed: %s (%d B)" % (path, len(data)))

    # --- keep the 2018 web app, out of the served folder ---
    mk = []
    for d in (ORIG, ORIG + "/static", ORIG + "/static/js", ORIG + "/static/css"):
        if not exists(out, d):
            mk.append("mkdir " + d)
    if mk:
        dbg(out, mk, write=True)
    for rel in OLD_FILES:
        p = PUB + "/" + rel
        if exists(out, p):
            # the 2018 original is kept once, like jooki.py does: a later image must not
            # replace it with the previous OpenJooki page of the same name
            if not exists(out, ORIG + "/" + rel):
                local = os.path.join(work, rel.replace("/", "_"))
                open(local, "wb").write(cat(out, p))
                put(out, local, ORIG + "/" + rel)
            dbg(out, ["rm " + p], write=True)
    for d in ("static/js", "static/css"):
        if exists(out, PUB + "/" + d):
            dbg(out, ["rmdir %s/%s" % (PUB, d)], write=True)
    # a file named config.js would be shadowed by web_ctrl's "/config" route
    if exists(out, PUB + "/config.js"):
        dbg(out, ["rm %s/config.js" % PUB], write=True)
    print("old web app moved to", ORIG)

    # --- new web page ---
    for f in WEB_FILES:
        put(out, os.path.join(WEBUI, f), PUB + "/" + f)
    for d in WEBUI_DIRS:
        put_dir(out, os.path.join(WEBUI, d), webui_dir_files(d), PUB + "/" + d)
    print("web page installed:", ", ".join(WEB_FILES + tuple("%s/ (%d files)" % (d, len(webui_dir_files(d))) for d in WEBUI_DIRS)))

    # --- system files (original kept once) ---
    sysfiles = system_files(core)   # the start script without the 1 s wait comes only with the 2.0 core
    for path, f in sorted(sysfiles.items()):
        if exists(out, path) and not exists(out, path + ".openjooki-orig"):
            local = os.path.join(work, os.path.basename(path) + ".orig")
            open(local, "wb").write(cat(out, path))
            put(out, local, path + ".openjooki-orig", mode="0100" + file_mode(path))
        put(out, os.path.join(SYSTEM_DIR, f), path, mode="0100" + file_mode(path))
    print("system files installed:", ", ".join(sorted(sysfiles)))

    # --- version ---
    vf = os.path.join(work, "version")
    open(vf, "w").write(version + "\n")
    put(out, vf, "/etc/openjooki-version")

    # --- no trace of the Jooki the base image was dumped from: its name and MAC address.
    # Every Jooki writes its own into both files at each boot (ml-jooki-hostname.sh, S31).
    NEUTRAL = {"/etc/hostname": b"jooki\n", "/etc/mac": b""}
    for path, data in NEUTRAL.items():
        local = os.path.join(work, os.path.basename(path) + ".neutral")
        open(local, "wb").write(data)
        put(out, local, path)
    # and nothing else of it: run-time files, stray files, keys; deleted files zeroed
    removed = scrub_rootfs(out, forget)
    print("leftovers removed: %s; free blocks zeroed%s" % (", ".join(removed) if removed else "none",
          "; none of %s left" % ", ".join(forget) if forget else ""))

    # --- checks ---
    r = subprocess.run(["e2fsck", "-fn", out], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("e2fsck reports problems:\n" + r.stdout + r.stderr)
    expect = {LIB: lib, "/etc/openjooki-version": (version + "\n").encode()}
    expect.update(side)   # /jooki/lib/core.lua read back too (ADR-0011)
    for f in WEB_FILES:
        expect[PUB + "/" + f] = open(os.path.join(WEBUI, f), "rb").read()
    for d in WEBUI_DIRS:
        for f in webui_dir_files(d):
            expect[PUB + "/" + d + "/" + f] = open(os.path.join(WEBUI, d, f), "rb").read()
    for path, f in sysfiles.items():
        expect[path] = open(os.path.join(SYSTEM_DIR, f), "rb").read()
    expect.update(NEUTRAL)
    for path, data in expect.items():
        if hashlib.sha256(cat(out, path)).hexdigest() != hashlib.sha256(data).hexdigest():
            raise SystemExit("read-back mismatch: " + path)
    if L.decode(cat(out, LIB + ".openjooki-orig")) != source:
        raise SystemExit("original player.lib copy mismatch")
    shutil.rmtree(work)
    print("OK: %s (e2fsck clean, %d files read back identical)" % (out, len(expect)))


if __name__ == "__main__":
    main()
