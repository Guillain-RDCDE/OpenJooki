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

No mount and no root needed: it edits the ext4 image with `debugfs` (e2fsprogs),
then checks it with `e2fsck -fn` and reads every written file back.

Usage: add-webui-to-image.py <in.img[.gz]> <out.img> <version>
Then:  scripts/make-release.sh <out.img> <version>
"""
import gzip, hashlib, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "tools", "openjooki")
sys.path.insert(0, TOOL)
import lua_patches as L  # noqa: E402
from jooki import SYSTEM_DIR, SYSTEM_FILES  # noqa: E402

WEBUI = os.path.join(TOOL, "webui")
WEB_FILES = ("index.html", "app.js", "app.css", "mqtt.js", "service-worker.js")
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


def main():
    if len(sys.argv) != 4:
        print(__doc__); sys.exit(1)
    src, out, version = sys.argv[1:]
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
    lib = L.encode(L.apply(source))
    open(os.path.join(work, "orig.lib"), "wb").write(base)
    open(os.path.join(work, "player.lib"), "wb").write(lib)
    if not exists(out, LIB + ".openjooki-orig"):
        put(out, os.path.join(work, "orig.lib"), LIB + ".openjooki-orig")
    put(out, os.path.join(work, "player.lib"), LIB)
    print("player.lib patched (%d fixes)" % len(L.P))

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
    print("web page installed:", ", ".join(WEB_FILES))

    # --- system files (original kept once) ---
    for path, f in sorted(SYSTEM_FILES.items()):
        if exists(out, path) and not exists(out, path + ".openjooki-orig"):
            local = os.path.join(work, os.path.basename(path) + ".orig")
            open(local, "wb").write(cat(out, path))
            put(out, local, path + ".openjooki-orig")
        put(out, os.path.join(SYSTEM_DIR, f), path)
    print("system files installed:", ", ".join(sorted(SYSTEM_FILES)))

    # --- version ---
    vf = os.path.join(work, "version")
    open(vf, "w").write(version + "\n")
    put(out, vf, "/etc/openjooki-version")

    # --- checks ---
    r = subprocess.run(["e2fsck", "-fn", out], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("e2fsck reports problems:\n" + r.stdout + r.stderr)
    expect = {LIB: lib, "/etc/openjooki-version": (version + "\n").encode()}
    for f in WEB_FILES:
        expect[PUB + "/" + f] = open(os.path.join(WEBUI, f), "rb").read()
    for path, f in SYSTEM_FILES.items():
        expect[path] = open(os.path.join(SYSTEM_DIR, f), "rb").read()
    for path, data in expect.items():
        if hashlib.sha256(cat(out, path)).hexdigest() != hashlib.sha256(data).hexdigest():
            raise SystemExit("read-back mismatch: " + path)
    if L.decode(cat(out, LIB + ".openjooki-orig")) != source:
        raise SystemExit("original player.lib copy mismatch")
    shutil.rmtree(work)
    print("OK: %s (e2fsck clean, %d files read back identical)" % (out, len(expect)))


if __name__ == "__main__":
    main()
