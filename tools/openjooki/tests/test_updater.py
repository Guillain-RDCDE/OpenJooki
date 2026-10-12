#!/usr/bin/env python3
"""The updater scripts the Jooki runs (docs/o.sh, docs/b.sh) check what they fetch before running it.

The real scripts run under busybox ash with nothing but busybox on the PATH, like on the device,
and a bench `curl` that serves files from a folder instead of GitHub (it also writes down every
address asked, in order). The device's own paths are used (/data/openjooki, /data/mender,
/etc/openjooki-version, /jooki/app/www/public): what was there is put back at the end.

  - scripts/make-release.sh writes the updater hashes into version.json, check_versions.py
    --manifest accepts them and refuses a copy that differs;
  - the right sha256: the update goes on (release copy first; the Pages copy when the release
    has none; the real openjooki-ota.sh then downloads, checks and hands the image over);
  - a wrong sha256: refused (exit 3, "updater rejected, nothing changed"), the old scripts kept,
    nothing run;
  - a release made before the hashes (2.4.1's version.json, as published): today's behaviour,
    the Pages copies, unchecked, and the log says "updater not verified";
  - no network: nothing changed.

  sudo python3 test_updater.py        (root, like every bench suite; busybox installed)
"""
import hashlib, os, shutil, subprocess, sys, tempfile
import bench as B

DOCS = os.path.join(B.REPO, "docs")
BASE = "github.com/Guillain-RDCDE/OpenJooki/releases/latest/download"
PAGES = "guillain-rdcde.github.io/OpenJooki"
WORK, STATUS = "/data/openjooki", "/jooki/app/www/public/openjooki-status.txt"
DEVTYPE, VERFILE = "/data/mender/device_type", "/etc/openjooki-version"
KEEP = [WORK, os.path.dirname(DEVTYPE), VERFILE, STATUS]      # put back as they were at the end
BUSYBOX = shutil.which("busybox")

# version.json of 2.4.1, the latest release when the hashes came in, as it is published
OLD_MANIFEST = """{
  "version": "2.4.1",
  "file": "openjooki-firmware-2.4.1.img.gz",
  "sha256": "5ab55db21b14532b31c5f36a932989fdec73672b20498e7842946e738f26d53f",
  "device_type": "ml-j2000",
  "date": "2026-10-07"
}
"""
FAKE_CURL = """#!%s ash
# the bench's curl: https://HOST/PATH is $FAKE_WEB/HOST/PATH (none: curl -f's exit 22); every address in $FAKE_LOG
out=; url=
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2;; --max-time) shift 2;; -*) shift;; *) url="$1"; shift;; esac
done
echo "$url" >> "$FAKE_LOG"
f="$FAKE_WEB/${url#https://}"
[ -f "$f" ] || exit 22
if [ -n "$out" ]; then cat "$f" > "$out"; else cat "$f"; fi
"""
# what the scripts would run, when they are not the real ones: each leaves a mark
STUB_OTA = b"#!/bin/ash\necho '[ota] stub updater ran'\necho ran > /data/openjooki/ota-ran\nexit 0\n"
STUB_SELF = b"#!/bin/ash\necho \"[self] stub installer ran with $1\"\necho \"$1\" > /data/openjooki/self-ran\nexit 0\n"
OLD = b"#!/bin/ash\n# the scripts of the previous update, which a refused one must leave alone\n"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def docs(name):
    with open(os.path.join(DOCS, name), "rb") as f:
        return f.read()


def manifest(version, image=b"", ota=None, self_=None):
    """A version.json in make-release.sh's shape; the updater hashes only when given."""
    lines = ['  "version": "%s"' % version, '  "file": "openjooki-firmware-%s.img.gz"' % version,
             '  "sha256": "%s"' % sha(image), '  "device_type": "ml-j2000"', '  "date": "2026-10-12"']
    if ota is not None:
        lines += ['  "ota_sha256": "%s"' % ota, '  "selfupdate_sha256": "%s"' % self_, '  "o_sha256": "%s"' % sha(docs("o.sh"))]
    return ("{\n" + ",\n".join(lines) + "\n}\n").encode()


class World:
    """The fake GitHub (files under web/), the busybox PATH, the device's paths saved and emptied."""
    def __init__(s):
        s.tmp = tempfile.mkdtemp(prefix="ojupd-")
        s.bin, s.web, s.log = (os.path.join(s.tmp, n) for n in ("bin", "web", "urls.log"))
        os.makedirs(s.bin)
        for name in subprocess.run([BUSYBOX, "--list"], capture_output=True, text=True, check=True).stdout.split():
            if name not in ("curl", "sleep"):
                os.symlink(BUSYBOX, os.path.join(s.bin, name))
        s._exe("curl", (FAKE_CURL % BUSYBOX).encode())
        s._exe("sleep", ("#!%s ash\nexit 0\n" % BUSYBOX).encode())    # dl()'s 5 s between retries: none here
        s.saved = os.path.join(s.tmp, "saved")
        os.makedirs(s.saved)
        for i, p in enumerate(KEEP):
            if os.path.lexists(p):
                shutil.move(p, os.path.join(s.saved, str(i)))

    def _exe(s, name, body):
        p = os.path.join(s.bin, name)
        with open(p, "wb") as f:
            f.write(body)
        os.chmod(p, 0o755)

    def restore(s):
        for i, p in enumerate(KEEP):
            if os.path.isdir(p) and not os.path.islink(p): shutil.rmtree(p)
            elif os.path.lexists(p): os.remove(p)
            if os.path.lexists(os.path.join(s.saved, str(i))):
                shutil.move(os.path.join(s.saved, str(i)), p)
        shutil.rmtree(s.tmp, ignore_errors=True)

    def reset(s, serve, installed=None, old_scripts=False):
        """A fresh device and a fresh GitHub serving `serve` ({"BASE/name" or "PAGES/name": bytes})."""
        for p in (WORK, s.web): shutil.rmtree(p, ignore_errors=True)
        for p in (WORK, os.path.dirname(DEVTYPE), os.path.dirname(STATUS)): os.makedirs(p, exist_ok=True)
        with open(DEVTYPE, "w") as f: f.write("device_type=ml-j2000\n")
        if installed is None:
            if os.path.exists(VERFILE): os.remove(VERFILE)
        else:
            with open(VERFILE, "w") as f: f.write(installed + "\n")
        for p in (STATUS, s.log):
            if os.path.exists(p): os.remove(p)
        if old_scripts:
            for n in ("ota.sh", "selfupdate.sh"):
                with open(os.path.join(WORK, n), "wb") as f: f.write(OLD)
        for where, body in serve.items():
            host, name = where.split("/", 1)
            p = os.path.join(s.web, {"BASE": BASE, "PAGES": PAGES}[host], name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f: f.write(body)

    def run(s, script):
        r = subprocess.run([BUSYBOX, "ash", os.path.join(DOCS, script)], capture_output=True, text=True, timeout=120,
                           cwd=s.tmp, env={"PATH": s.bin, "FAKE_WEB": s.web, "FAKE_LOG": s.log, "HOME": "/root"})
        return r.returncode, read(STATUS), r.stdout + r.stderr

    def urls(s):
        return [u.replace("https://", "").replace(BASE, "BASE").replace(PAGES, "PAGES") for u in read(s.log).split()]


def read(p, mode="r"):
    try:
        with open(p, mode) as f: return f.read()
    except FileNotFoundError:
        return b"" if "b" in mode else ""


def work(name, mode="rb"):
    return read(os.path.join(WORK, name), mode)


def main():
    R = B.Results()
    if not BUSYBOX:
        print("busybox is needed (apt install busybox)"); sys.exit(1)
    real_ota, real_self = docs("openjooki-ota.sh"), docs("openjooki-selfupdate.sh")
    image = os.urandom(4096)
    w = World()
    try:
        # --- 1. make-release.sh: the hashes in version.json, the scripts next to it; check_versions agrees
        rel = os.path.join(w.tmp, "rel")
        os.makedirs(rel)
        with open(os.path.join(rel, "out.img.gz"), "wb") as f: f.write(image)
        mk = subprocess.run(["bash", os.path.join(B.REPO, "scripts", "make-release.sh"), "out.img.gz", "9.9.9"],
                            cwd=rel, capture_output=True, text=True)
        man_path = os.path.join(rel, "release-9.9.9", "version.json")
        man = read(man_path, "rb")
        R.check("make-release.sh: version.json gives ota_sha256, selfupdate_sha256, o_sha256 of docs/",
                mk.returncode == 0 and b'"ota_sha256": "%s"' % sha(real_ota).encode() in man
                and b'"selfupdate_sha256": "%s"' % sha(real_self).encode() in man
                and b'"o_sha256": "%s"' % sha(docs("o.sh")).encode() in man, mk.stdout[-300:] + mk.stderr[-300:] + man.decode())
        R.check("make-release.sh: the two scripts are next to version.json (publish-release.sh attaches them)",
                read(os.path.join(rel, "release-9.9.9", "openjooki-ota.sh"), "rb") == real_ota
                and read(os.path.join(rel, "release-9.9.9", "openjooki-selfupdate.sh"), "rb") == real_self)
        cv = lambda: subprocess.run([sys.executable, os.path.join(B.REPO, "scripts", "check_versions.py"), "--manifest", man_path],
                                    capture_output=True, text=True)
        r = cv()
        R.check("check_versions.py --manifest: the hashes are the committed scripts'", r.returncode == 0, r.stdout + r.stderr)
        with open(os.path.join(rel, "release-9.9.9", "openjooki-ota.sh"), "ab") as f: f.write(b"# changed\n")
        r = cv()
        R.check("check_versions.py --manifest: a copy that is not the manifest's is refused",
                r.returncode != 0 and "openjooki-ota.sh" in r.stdout, r.stdout + r.stderr)

        # --- 2. o.sh, the manifest make-release.sh wrote, the release's copies: verified, then the real
        # openjooki-ota.sh runs (installed = released version: nothing to install, the installer never runs)
        w.reset({"BASE/version.json": man, "BASE/openjooki-ota.sh": real_ota, "BASE/openjooki-selfupdate.sh": real_self},
                installed="9.9.9")
        rc, st, out = w.run("o.sh")
        R.check("o.sh, hashes in the release: verified from the release's copies, the real updater runs",
                rc == 0 and "updater verified" in st and "already up to date" in st and "not verified" not in st, (rc, st, out))
        R.check("o.sh, hashes in the release: version.json first, then the release's copies, never Pages",
                w.urls()[:3] == ["BASE/version.json", "BASE/openjooki-ota.sh", "BASE/openjooki-selfupdate.sh"]
                and not any(u.startswith("PAGES/") for u in w.urls()), w.urls())
        R.check("o.sh, hashes in the release: the verified scripts are in place, executable, no leftover",
                work("ota.sh") == real_ota and work("selfupdate.sh") == real_self and os.access(os.path.join(WORK, "ota.sh"), os.X_OK)
                and not os.path.exists(os.path.join(WORK, "ota.sh.new")) and not os.path.exists(os.path.join(WORK, "selfupdate.sh.new")))

        # --- 3. the update goes on: the real openjooki-ota.sh downloads the image, checks it and hands it
        # to the installer (a stub here: the real one writes partitions)
        new = manifest("9.9.10", image, sha(real_ota), sha(STUB_SELF))
        for script in ("o.sh", "b.sh"):
            w.reset({"BASE/version.json": new, "BASE/openjooki-ota.sh": real_ota, "BASE/openjooki-selfupdate.sh": STUB_SELF,
                     "BASE/openjooki-firmware-9.9.10.img.gz": image}, installed="9.9.9", old_scripts=True)
            rc, st, out = w.run(script)
            R.check("%s, right sha256: the update goes on (image downloaded, intact, handed to the installer)" % script,
                    "updater verified" in st and "image intact" in st and "stub installer ran with" in st
                    and work("self-ran", "r").strip().endswith("openjooki-firmware-9.9.10.img.gz"), (rc, st, out))

        # --- 4. no copy in the release (or a bad one there): the Pages copy, if it has the sha256
        for label, serve in (("the release has no copy", {}),
                             ("the release's copy is not the right one", {"BASE/openjooki-ota.sh": STUB_OTA + b"# not this\n"})):
            w.reset(dict(serve, **{"BASE/version.json": manifest("9.9.10", image, sha(STUB_OTA), sha(STUB_SELF)),
                                   "PAGES/openjooki-ota.sh": STUB_OTA, "PAGES/openjooki-selfupdate.sh": STUB_SELF}),
                    old_scripts=True)
            rc, st, out = w.run("o.sh")
            R.check("o.sh, %s: the Pages copy is checked and used" % label,
                    rc == 0 and "updater verified" in st and work("ota-ran") == b"ran\n" and work("ota.sh") == STUB_OTA
                    and w.urls()[:3] == ["BASE/version.json", "BASE/openjooki-ota.sh", "PAGES/openjooki-ota.sh"], (rc, st, w.urls()))

        # --- 5. a wrong sha256, wherever the copy comes from: refused, the old scripts kept, nothing run
        bad = STUB_OTA + b"# someone else's\n"
        cases = [("o.sh", "updater (both copies) not the release's", {"BASE/openjooki-ota.sh": bad, "PAGES/openjooki-ota.sh": bad,
                                                                     "PAGES/openjooki-selfupdate.sh": STUB_SELF}),
                 ("o.sh", "installer not the release's", {"PAGES/openjooki-ota.sh": STUB_OTA, "PAGES/openjooki-selfupdate.sh": bad}),
                 ("b.sh", "updater not the release's", {"PAGES/openjooki-ota.sh": bad, "PAGES/openjooki-selfupdate.sh": STUB_SELF})]
        for script, label, serve in cases:
            w.reset(dict(serve, **{"BASE/version.json": manifest("9.9.10", image, sha(STUB_OTA), sha(STUB_SELF))}), old_scripts=True)
            rc, st, out = w.run(script)
            R.check("%s, %s: refused, exit 3, 'updater rejected, nothing changed'" % (script, label),
                    rc == 3 and "updater rejected, nothing changed" in st and "ERROR" in st, (rc, st, out))
            R.check("%s, %s: the old scripts kept, no downloaded file left, nothing run" % (script, label),
                    work("ota.sh") == OLD and work("selfupdate.sh") == OLD and sorted(os.listdir(WORK)) == ["ota.sh", "selfupdate.sh", "version.json"]
                    and "stub" not in st, (sorted(os.listdir(WORK)), st))

        # --- 6. the releases made before the hashes (2.4.1's version.json as published): as before
        for script in ("o.sh", "b.sh"):
            w.reset({"BASE/version.json": OLD_MANIFEST.encode(), "PAGES/openjooki-ota.sh": real_ota,
                     "PAGES/openjooki-selfupdate.sh": real_self}, installed="2.4.1", old_scripts=True)
            rc, st, out = w.run(script)
            # the real openjooki-ota.sh finds 2.4.1 installed: exit 0, which both report as they always did
            R.check("%s, a release without hashes: 'updater not verified', then today's behaviour (Pages copies, the real updater)" % script,
                    rc == 0 and "updater not verified" in st and "updater verified" not in st and "already up to date" in st
                    and work("ota.sh") == real_ota and work("selfupdate.sh") == real_self, (rc, st, out))
            R.check("%s, a release without hashes: the release is never asked for the scripts" % script,
                    w.urls() == ["BASE/version.json", "PAGES/openjooki-ota.sh", "PAGES/openjooki-selfupdate.sh", "BASE/version.json"],
                    w.urls())

        # --- 7. no network: nothing changed
        for script in ("o.sh", "b.sh"):
            w.reset({}, old_scripts=True)
            rc, st, out = w.run(script)
            R.check("%s, no network: exit 1, 'cannot reach GitHub', nothing changed" % script,
                    rc == 1 and "cannot reach GitHub" in st and work("ota.sh") == OLD and work("selfupdate.sh") == OLD, (rc, st, out))
    finally:
        w.restore()
    R.finish(list_failed=True, ok_line="OK: the updater scripts are checked before they run (and run as before without hashes)")


if __name__ == "__main__":
    main()
