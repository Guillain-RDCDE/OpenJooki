#!/usr/bin/env python3
"""OpenJooki - rebuild the ORIGINAL Jooki 2 system (Muuselabs, December 2022) from an OpenJooki
release image, for the "original Jooki" card: a Jooki as it was sold, without OpenJooki.

Every OpenJooki image keeps each file it replaces, once, as <file>.openjooki-orig, and the 2018
web app in /jooki/app/www/public-openjooki-orig/ (scripts/add-webui-to-image.py, tools/openjooki/
jooki.py). This puts every one of them back in place (the same inode: owner, mode and dates as
they were), removes what OpenJooki added, and checks the result:

  sudo python3 make_original_rootfs.py openjooki-firmware-2.0.5.img.gz out/original-rootfs.img \\
       [--check jooki-system.tar.gz] [--forget jooki2-0426E8 ...]

  --check   a tar of /jooki taken on a Jooki BEFORE OpenJooki (tools/openjooki/jooki.py backup):
            every file of jooki/app, jooki/bin and jooki/lib must come back byte for byte, and
            nothing may be left there that the tar does not have. The first OpenJooki images kept
            their own page as the "original" index.html and service-worker.js: those two come
            from this tar.
  --forget  strings that must not appear anywhere in the result

The Jooki's name and MAC address stay neutral (/etc/hostname, /etc/mac): the original system
writes its own at every start. No mount: the ext4 image is edited with debugfs, like the release.
"""
import argparse, hashlib, os, shutil, sys, tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_card_image import debugfs_cat, debugfs_exists, debugfs_ls, debugfs_w, run, scrub_rootfs, ungz  # noqa: E402

ORIG = ".openjooki-orig"
PUB = "/jooki/app/www/public"
PUB_ORIG = "/jooki/app/www/public-openjooki-orig"
# added by OpenJooki, with no original to put back (tools/openjooki/jooki.py WEBUI_FILES, system files)
ADDED = ("/etc/openjooki-version", "/etc/rcS.d/S57_oj-security.sh", "/etc/mosquitto/mosquitto.conf.openjooki-base",
         "/jooki/lib/core.lua",                             # the core itself since ADR-0011 (player.lib is the loader)
         PUB + "/app.js", PUB + "/app.css", PUB + "/mqtt.js", PUB + "/manifest.json", PUB + "/icon-192.png",
         PUB + "/icon-512.png", PUB + "/apple-touch-icon.png", PUB + "/index.html",
         PUB + "/service-worker.js",                           # shipped until 2.2.5: images of that age still carry it
         PUB + "/mp3-worker.js", PUB + "/lame.min.js", PUB + "/lame.LICENSE.txt",
         PUB + "/oj-auth.json", PUB + "/openjooki-status.txt")
ADDED_DIRS = (PUB + "/tokimg",)                          # jooki.py WEBUI_DIRS: the token pictures
CHECKED = ("jooki/app/", "jooki/bin/", "jooki/lib/")    # what a pre-OpenJooki backup holds of the system


def is_dir(mode): return (mode & 0o170000) == 0o040000


def walk(img, top):
    """Every path under top: [(path, mode)]."""
    out = []
    for name, mode in debugfs_ls(img, top):
        p = top.rstrip("/") + "/" + name
        out.append((p, mode))
        if is_dir(mode):
            out += walk(img, p)
    return out


def restore(img):
    done = []
    # 1. each replaced file: the original inode takes its name back
    for top in ("/etc", "/jooki"):
        for p, mode in walk(img, top):
            if p.endswith(ORIG) and not is_dir(mode):
                target = p[:-len(ORIG)]
                cmds = ["rm " + target] if debugfs_exists(img, target) else []
                debugfs_w(img, cmds + ["ln %s %s" % (p, target), "unlink " + p])
                done.append(target)
    # 2. what OpenJooki added
    for p in ADDED:
        if debugfs_exists(img, p):
            debugfs_w(img, ["rm " + p]); done.append("-" + p)
    for d in ADDED_DIRS:
        if debugfs_exists(img, d):
            debugfs_w(img, ["rm " + p for p, mode in walk(img, d) if not is_dir(mode)] + ["rmdir " + d]); done.append("-" + d + "/")
    # 3. the 2018 web app back in the served folder
    if debugfs_exists(img, PUB_ORIG):
        for p, mode in walk(img, PUB_ORIG):
            target = PUB + p[len(PUB_ORIG):]
            if is_dir(mode):
                if not debugfs_exists(img, target):
                    debugfs_w(img, ["mkdir " + target])
            else:
                debugfs_w(img, ["ln %s %s" % (p, target), "unlink " + p])
                done.append(target)
        for p, mode in reversed(walk(img, PUB_ORIG)):
            debugfs_w(img, ["rmdir " + p])
        debugfs_w(img, ["rmdir " + PUB_ORIG])
    return done


def web_from_backup(img, tar_path):
    """The first OpenJooki images kept their own page as the "original" index.html and
    service-worker.js (fixed since in add-webui-to-image.py): take the 2018 ones from the backup."""
    fixed = []
    with tarfile.open(tar_path) as t:
        for name in ("index.html", "service-worker.js"):
            p = PUB + "/" + name
            if b"OpenJooki" not in debugfs_cat(img, p):
                continue
            m = t.getmember("jooki/app/www/public/" + name)
            local = os.path.join(os.path.dirname(os.path.abspath(img)), ".orig-" + name)
            open(local, "wb").write(t.extractfile(m).read())
            debugfs_w(img, ["rm " + p, "write %s %s" % (local, p), "set_inode_field %s mode 0100%o" % (p, m.mode & 0o7777),
                            "set_inode_field %s uid 0" % p, "set_inode_field %s gid 0" % p])
            os.unlink(local); fixed.append(p)
    return fixed


def check_against(img, tar_path):
    """Byte-for-byte against a pre-OpenJooki backup, in both directions, for jooki/app, bin, lib."""
    want = {}
    with tarfile.open(tar_path) as t:
        for m in t.getmembers():
            name = m.name.lstrip("./")
            if m.isfile() and name.startswith(CHECKED):
                want["/" + name] = hashlib.sha256(t.extractfile(m).read()).hexdigest()
    bad = [p for p, h in sorted(want.items()) if hashlib.sha256(debugfs_cat(img, p)).hexdigest() != h]
    have = set()
    for top in CHECKED:
        for p, mode in walk(img, "/" + top.rstrip("/")):
            if not is_dir(mode) and (mode & 0o170000) == 0o100000:
                have.add(p)
    extra = sorted(have - set(want))
    if bad or extra:
        raise SystemExit("not the original system:\n  differ: %s\n  not in the backup: %s" % (bad, extra))
    return len(want)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("release"); ap.add_argument("out")
    ap.add_argument("--check", help="tar of /jooki taken before OpenJooki")
    ap.add_argument("--forget", action="append", default=[])
    a = ap.parse_args()
    for t in ("debugfs", "e2fsck"):
        if not shutil.which(t):
            raise SystemExit("missing tool: " + t)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    if a.release.endswith(".gz"):
        ungz(a.release, a.out)
    else:
        shutil.copyfile(a.release, a.out)
    if not debugfs_exists(a.out, "/etc/openjooki-version"):
        raise SystemExit("not an OpenJooki release image (no /etc/openjooki-version)")
    done = restore(a.out)
    if a.check:
        fixed = web_from_backup(a.out, a.check)
        if fixed:
            print("2018 web page taken from the backup: %s" % ", ".join(fixed))
    elif any(b"OpenJooki" in debugfs_cat(a.out, PUB + "/" + n) for n in ("index.html", "service-worker.js")):
        raise SystemExit("this image kept an early OpenJooki page as the original: give --check <backup tar>")
    left = [p for top in ("/etc", "/jooki") for p, _ in walk(a.out, top) if "openjooki" in p.lower()]
    if left:
        raise SystemExit("OpenJooki files left: %s" % left)
    removed = scrub_rootfs(a.out, a.forget)
    run(["e2fsck", "-fn", a.out])
    print("original system: %d files put back or removed; leftovers removed: %s; e2fsck clean; %s"
          % (len(done), ", ".join(removed) or "none", debugfs_cat(a.out, "/etc/mender/artifact_info").decode().strip()))
    if a.check:
        print("checked against %s: %d files identical, nothing extra" % (os.path.basename(a.check), check_against(a.out, a.check)))


if __name__ == "__main__":
    main()
