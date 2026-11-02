#!/usr/bin/env python3
"""The spotify_ctrl patch (spotify_direct.py) and how patch webui takes it.

The patch is built from the Jooki's own spotify_ctrl, and only for the build it was made for.
No Spotify executable is in the repository, so these checks use other bytes; the known build
is checked on the Jooki itself (the sha256 of the result is in spotify_direct.py).

  - any other build: no patch, and patch webui installs neither spotify_ctrl nor the flag;
  - the new handler fits the old one's 164 bytes and returns with jr ra.

  python3 test_spotify_direct.py        (no core, no root)
"""
import os, struct, sys, types
import bench as B
sys.path.insert(0, os.path.join(B.REPO, "tools", "openjooki"))
import jooki, spotify_direct as D

R = B.Results(lead=""); check = R.check

# SD1 an unknown build is left alone
check("SD1 other bytes: no patch", D.patch(b"\0" * 596308) is None)
check("SD1 ... and not taken for the patched build", not D.is_patched(b"\0" * 596308))

# SD2 the handler
code = D._handler()
words = struct.unpack("<%dI" % (len(code) // 4), code)
check("SD2 the handler is the old one's size", len(code) == D.END - D.START, len(code))
check("SD2 ... and returns with jr ra", 0x03e00008 in words, [hex(w) for w in words])

# SD3 patch webui with an unknown spotify_ctrl: nothing Spotify in the files it installs
jooki.ssh_bytes = lambda host, cmd, data=None, timeout=120: types.SimpleNamespace(stdout=b"\0" * 1000, returncode=0)
said = []
jooki.log = lambda *x: said.append(" ".join(str(y) for y in x))
check("SD3 unknown build: no files", jooki.spotify_direct_files("jooki") == {})
check("SD3 ... and the update says so", any("unknown build" in s for s in said), said)

R.finish()
