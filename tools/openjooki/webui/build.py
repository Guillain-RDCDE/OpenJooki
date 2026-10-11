#!/usr/bin/env python3
"""Assemble the page's script: src/*.js, in name order, put end to end inside one closure -> app.js.

  python3 tools/openjooki/webui/build.py           # writes app.js and the copies in docs/
  python3 tools/openjooki/webui/build.py --check   # fails if app.js is not what src/ gives,
                                                   # or a copy in docs/ is not what webui/ gives (CI)

Nothing is transformed: app.js is the files of src/ one after the other, readable as they are.
The Jooki serves app.js only (jooki.py WEBUI_FILES); src/ is where the page is edited. Each file of
src/ is a run of statements of the same function, so they share their variables like one file did.

The MP3 encoder (mp3-worker.js, lame.min.js, lame.LICENSE.txt) is also used by Jookistory on the
website (docs/studio.html, served by GitHub Pages from docs/). webui/ is the one place to edit it;
docs/ gets a copy. Only the first comment of mp3-worker.js differs: it says which page loads it.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "app.js")
DOCS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "docs"))
# webui file -> its copy in docs/, with the exact lines that change (each must be found once)
COPIES = [
    ("mp3-worker.js", [
        (b"off the page's main thread (app.js, \"discs\").\n",
         b"off the page's main thread (docs/studio.html; a copy of tools/openjooki/webui/mp3-worker.js).\n"),
        (b"(LGPL-3.0, lame.LICENSE.txt), loaded from the Jooki itself. */\n",
         b"(LGPL-3.0, lame.LICENSE.txt), served next to the page. */\n"),
    ]),
    ("lame.min.js", []),
    ("lame.LICENSE.txt", []),
]
HEAD = (b"/* OpenJooki web UI \xe2\x80\x94 local management page for a Jooki v2.\n"
        b"   Talks to the Jooki only (MQTT over WebSocket on port 8000 + HTTP /upload).\n"
        b"   No tracker, no cloud, no external resource. */\n"
        b"(function () {\n"
        b"  'use strict';\n"
        b"\n")
TAIL = b"})();\n"


def build():
    names = sorted(f for f in os.listdir(SRC) if f.endswith(".js"))
    parts = []
    for n in names:
        with open(os.path.join(SRC, n), "rb") as f:
            b = f.read().replace(b"\r\n", b"\n")
        if not b.endswith(b"\n"):
            raise SystemExit("src/%s does not end with a newline" % n)
        parts.append(b)
    return HEAD + b"".join(parts) + TAIL, names


def copies():
    """[(path in docs/, bytes it must hold)], made from the webui files."""
    out = []
    for name, edits in COPIES:
        with open(os.path.join(HERE, name), "rb") as f:
            b = f.read().replace(b"\r\n", b"\n")
        for old, new in edits:
            if b.count(old) != 1:
                raise SystemExit("webui/%s: %r is not there once; update COPIES in build.py" % (name, old))
            b = b.replace(old, new)
        out.append((os.path.join(DOCS, name), b))
    return out


def main():
    out, names = build()
    docs = copies()
    if "--check" in sys.argv:
        bad = 0
        with open(OUT, "rb") as f:
            cur = f.read().replace(b"\r\n", b"\n")
        if cur != out:
            print("app.js is not what src/ gives: edit src/*.js, then run tools/openjooki/webui/build.py")
            bad = 1
        for path, want in docs:
            with open(path, "rb") as f:
                cur = f.read().replace(b"\r\n", b"\n")
            if cur != want:
                n = os.path.basename(path)
                print("docs/%s is not the copy of webui/%s: edit webui/%s, then run tools/openjooki/webui/build.py"
                      % (n, n, n))
                bad = 1
        if bad:
            return 1
        print("app.js matches src/ (%d files, %d bytes); the %d copies in docs/ match webui/"
              % (len(names), len(out), len(docs)))
        return 0
    with open(OUT, "wb") as f:
        f.write(out)
    for path, want in docs:
        with open(path, "wb") as f:
            f.write(want)
    print("app.js written: %d files, %d bytes; %d copies written to docs/" % (len(names), len(out), len(docs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
