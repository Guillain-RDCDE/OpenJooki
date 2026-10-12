#!/usr/bin/env python3
"""The one version number, wherever it is written by hand, must agree (a CI gate).

  python3 scripts/check_versions.py                 # the page, its cache keys, the README and the changelog agree
  python3 scripts/check_versions.py --release 2.2.6 # and the changelog's top entry is that very release
  python3 scripts/check_versions.py --release 2.2.6 --manifest release-2.2.6/version.json
                                                    # and the manifest's updater hashes are the committed scripts'

Places: tools/openjooki/webui/app.js (VERSION; built from webui/src, which build.py --check guards), tools/openjooki/webui/index.html (three ?v=),
README.md ("**New in X:**"), CHANGELOG.md (first "## " heading: "## Next release" while work is
in progress, "## OpenJooki X (date) — title" once released). The firmware images and manifests
take the version from the build arguments (scripts/release.sh), not from here.

--manifest: version.json (scripts/make-release.sh) gives the sha256 of the updater scripts that
o.sh and b.sh check on the Jooki. Each must be the sha256 of the committed docs/ script (git's
copy when git is there, else the file with LF line endings, as .gitattributes stores it) and of
the copy next to the manifest, the one scripts/publish-release.sh attaches to the release.
"""
import hashlib, json, re, subprocess, sys, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# manifest field -> the script it is the sha256 of (in docs/; also next to the manifest unless None)
UPDATER_HASHES = [("ota_sha256", "openjooki-ota.sh", True),
                  ("selfupdate_sha256", "openjooki-selfupdate.sh", True),
                  ("o_sha256", "o.sh", False)]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def committed(rel):
    """The bytes of a file as committed at HEAD; outside a git checkout (the bench's copies) or
    without git, the file with LF line endings."""
    if os.path.exists(os.path.join(ROOT, ".git")):
        try:
            return subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + rel], capture_output=True,
                                  check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            pass
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read().replace(b"\r\n", b"\n")


def check_manifest(path, problems):
    with open(path, encoding="utf-8") as f:
        man = json.load(f)
    here = os.path.dirname(os.path.abspath(path))
    for field, script, attached in UPDATER_HASHES:
        want = man.get(field)
        if not re.fullmatch(r"[0-9a-f]{64}", str(want or "")):
            problems.append("%s: %s is %r, expected a sha256" % (path, field, want))
            continue
        got = hashlib.sha256(committed("docs/" + script)).hexdigest()
        if got != want:
            problems.append("%s: %s is not the committed docs/%s (%s): rebuild the release" % (path, field, script, got))
        if attached:
            copy = os.path.join(here, script)
            if not os.path.isfile(copy):
                problems.append("%s: missing next to the manifest (scripts/make-release.sh copies it)" % copy)
            else:
                with open(copy, "rb") as f:
                    if hashlib.sha256(f.read()).hexdigest() != want:
                        problems.append("%s: its sha256 is not the manifest's %s" % (copy, field))


def main():
    release = sys.argv[sys.argv.index("--release") + 1] if "--release" in sys.argv else None
    manifest = sys.argv[sys.argv.index("--manifest") + 1] if "--manifest" in sys.argv else None
    problems = []
    if manifest:
        check_manifest(manifest, problems)
    app = re.search(r"^  var VERSION = '([^']+)';", read("tools/openjooki/webui/app.js"), re.M)
    version = app.group(1) if app else None
    if not version:
        problems.append("app.js: no VERSION line")
    keys = re.findall(r"\?v=([0-9A-Za-z.\-]+)", read("tools/openjooki/webui/index.html"))
    if len(keys) != 3 or set(keys) != {version}:
        problems.append("index.html: cache keys %r, expected three times %r" % (keys, version))
    readme = re.search(r"^\*\*New in ([^:]+):\*\*", read("README.md"), re.M)
    if not readme or readme.group(1) != version:
        problems.append("README.md: 'New in %s', expected %r" % (readme.group(1) if readme else None, version))
    head = re.search(r"^## (.+)$", read("CHANGELOG.md"), re.M).group(1)
    m = re.match(r"OpenJooki (\S+) \(\d{1,2} [A-Z][a-z]+ \d{4}\) — .+", head)
    if head != "Next release" and not m:
        problems.append("CHANGELOG.md: first heading %r is neither 'Next release' nor 'OpenJooki X (D Month YYYY) — title'" % head)
    if m and m.group(1) != version:
        problems.append("CHANGELOG.md: top entry is %s, the page says %s" % (m.group(1), version))
    if release:
        if release != version:
            problems.append("release %s asked, the page says %s (scripts/bump-version.sh first)" % (release, version))
        if not m or m.group(1) != release:
            problems.append("CHANGELOG.md: the top entry must be 'OpenJooki %s (date) — title', not %r" % (release, head))
    if problems:
        print("version check FAILED:\n  " + "\n  ".join(problems))
        return 1
    print("versions agree: %s%s%s" % (version, " (release entry present)" if m else " (changelog: Next release)",
                                      "; %s: updater hashes are the committed scripts'" % manifest if manifest else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
