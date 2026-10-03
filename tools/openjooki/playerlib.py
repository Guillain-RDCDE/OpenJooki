# -*- coding: utf-8 -*-
"""The container of /jooki/lib/player.lib, the file the Jooki's closed C host runs.

Lua 5.1 source, zlib-compressed, its first two bytes XOR-ed with its last two. The original
program used it; since ADR-0011 the file is OpenJooki's small loader (tools/build/bundle.py),
which reads the real core from /jooki/lib/core.lua. Used by the build, the device tool, the
release image script and the loader test: one codec, here.
"""
import zlib

MAX_SIZE = 204800          # the host decompresses into a fixed 200 KiB buffer (ADR-0001)


def decode(blob):
    """player.lib bytes -> Lua source (latin-1, byte for byte)."""
    d = bytearray(blob)
    d[0] ^= d[-1]; d[1] ^= d[-2]
    return zlib.decompress(bytes(d)).decode("latin-1")


def encode(src):
    """Lua source -> player.lib bytes. Refuses what the host could not hold."""
    raw = src.encode("latin-1")
    if len(raw) >= MAX_SIZE:
        raise ValueError("player.lib source too big (%d >= %d)" % (len(raw), MAX_SIZE))
    c = bytearray(zlib.compress(raw, 9))
    c[0] ^= c[-1]; c[1] ^= c[-2]
    return bytes(c)


def is_openjooki(src):
    """True when this source is OpenJooki's (the 2.x loader or core, or a 1.x patched program),
       not the Jooki's original program."""
    return "_OPENJOOKI_" in src[:400]
