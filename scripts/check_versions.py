#!/usr/bin/env python3
"""The one version number, wherever it is written by hand, must agree (a CI gate).

  python3 scripts/check_versions.py                 # the page, its cache keys, the README and the changelog agree
  python3 scripts/check_versions.py --release 2.2.6 # and the changelog's top entry is that very release

Places: tools/openjooki/webui/app.js (VERSION; built from webui/src, which build.py --check guards), tools/openjooki/webui/index.html (three ?v=),
README.md ("**New in X:**"), CHANGELOG.md (first "## " heading: "## Next release" while work is
in progress, "## OpenJooki X (date) — title" once released). The firmware images and manifests
take the version from the build arguments (scripts/release.sh), not from here.
"""
import re, sys, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def main():
    release = sys.argv[sys.argv.index("--release") + 1] if "--release" in sys.argv else None
    problems = []
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
    print("versions agree: %s%s" % (version, " (release entry present)" if m else " (changelog: Next release)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
