#!/usr/bin/env python3
"""Assemble the page's script: src/*.js, in name order, put end to end inside one closure -> app.js.

  python3 tools/openjooki/webui/build.py           # writes app.js
  python3 tools/openjooki/webui/build.py --check   # fails if app.js is not what src/ gives (CI)

Nothing is transformed: app.js is the files of src/ one after the other, readable as they are.
The Jooki serves app.js only (jooki.py WEBUI_FILES); src/ is where the page is edited. Each file of
src/ is a run of statements of the same function, so they share their variables like one file did.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "app.js")
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


def main():
    out, names = build()
    if "--check" in sys.argv:
        with open(OUT, "rb") as f:
            cur = f.read().replace(b"\r\n", b"\n")
        if cur != out:
            print("app.js is not what src/ gives: edit src/*.js, then run tools/openjooki/webui/build.py")
            return 1
        print("app.js matches src/ (%d files, %d bytes)" % (len(names), len(out)))
        return 0
    with open(OUT, "wb") as f:
        f.write(out)
    print("app.js written: %d files, %d bytes" % (len(names), len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
