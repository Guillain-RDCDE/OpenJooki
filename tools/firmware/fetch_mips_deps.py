#!/usr/bin/env python3
"""Fetch checksum-pinned sources for a static musl MIPS32r2 / FP32 controller build."""
import argparse
from pathlib import Path
from prepare import checked_download

SOURCES = (
    ("https://musl.libc.org/releases/musl-1.2.3.tar.gz", "musl-1.2.3.tar.gz", "7d5b0b6062521e4627e099e4c9dc8248d32a30285e959b7eecaa780cf8cfd4a4"),
    ("https://mosquitto.org/files/source/mosquitto-1.6.12.tar.gz", "mosquitto-1.6.12.tar.gz", "548d73d19fb787dd0530334e398fd256ef3a581181678488a741a995c4f007fb"),
    ("https://codeload.github.com/protobuf-c/protobuf-c/tar.gz/refs/tags/v1.3.3", "protobuf-c-v1.3.3.tar.gz", "8515da8b84ea36768ae69a52f9ede8d718936d6058077265b6e458cfc55f8bdb"),
)
if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    a = p.parse_args()
    for url, name, digest in SOURCES:
        print(checked_download(url, digest, a.source / name))
