#!/usr/bin/env python3
"""Builds docs/Jooki-SD-Card-mac.zip: the Mac app with jooki_sd.py inside (Contents/Resources),
executable bits set, so that it runs once unzipped.   python3 tools/sdcard/make_mac_zip.py"""
import os, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = "Jooki SD Card.app"
OUT = os.path.join(HERE, "..", "..", "docs", "Jooki-SD-Card-mac.zip")
FIXED = (2026, 1, 1, 0, 0, 0)          # same bytes at every build


def add(z, arcname, data, mode):
    info = zipfile.ZipInfo(arcname, FIXED)
    info.create_system = 3                              # "made on Unix": otherwise unzippers ignore the modes
    info.external_attr = (0o100000 | mode) << 16      # regular file + permissions
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, data)


with zipfile.ZipFile(OUT, "w") as z:
    base = os.path.join(HERE, APP)
    add(z, APP + "/Contents/Info.plist", open(os.path.join(base, "Contents", "Info.plist"), "rb").read(), 0o644)
    add(z, APP + "/Contents/MacOS/Jooki SD Card", open(os.path.join(base, "Contents", "MacOS", "Jooki SD Card"), "rb").read(), 0o755)
    add(z, APP + "/Contents/Resources/jooki_sd.py", open(os.path.join(HERE, "jooki_sd.py"), "rb").read(), 0o755)
print("wrote", os.path.normpath(OUT), os.path.getsize(OUT), "bytes")
