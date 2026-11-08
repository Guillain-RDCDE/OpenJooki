#!/usr/bin/env python3
"""Deterministic ESP32 firmware packages and read-only validation of original recovery packages.
Checks package contents and flash regions. It never connects to or flashes a device.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import shlex
import tarfile

EPOCH = 1669852800
EXPECTED = {0x1000, 0x8000, 0xD000, 0x10000}

def validate(files, expected_sha=None, archive_bytes=None):
    if expected_sha is not None:
        if archive_bytes is None or hashlib.sha256(archive_bytes).hexdigest() != expected_sha:
            raise ValueError("package SHA-256 does not match the backed-up original")
    args = json.loads(files["esp32/flasher_args.json"])
    mapped = args["flash_files"]
    if {int(k, 0) for k in mapped} != EXPECTED:
        raise ValueError("unexpected flash layout; refusing to package")
    regions = []
    for offset, name in mapped.items():
        if not isinstance(name, str) or name.startswith("/") or ".." in Path(name).parts:
            raise ValueError("unsafe flash filename")
        data = files["esp32/" + name]
        start = int(offset, 0)
        if not data or start + len(data) > 16 * 1024 * 1024:
            raise ValueError("empty / oversized flash region")
        if start in (0x1000, 0x10000) and data[0] != 0xE9:
            raise ValueError("not an ESP32 bootloader / application image")
        regions.append((start, start + len(data), name, data))
    regions.sort()
    if any(a[1] > b[0] for a, b in zip(regions, regions[1:])):
        raise ValueError("flash regions overlap")
    script = files["esp32/flash.sh"].decode()
    tokens = shlex.split(script, comments=True)
    if "write_flash" not in tokens: raise ValueError("recovery script has no write_flash")
    for offset, name in mapped.items():
        if offset not in tokens or tokens[tokens.index(offset) + 1] != name:
            raise ValueError("recovery script does not match flasher_args.json")
    return {"sha256": hashlib.sha256(archive_bytes).hexdigest() if archive_bytes else None,
            "files": [{"offset": hex(start), "file": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                      for start, _, name, data in regions],
            "scope": "package and flash-layout validation only; no physical restore tested"}

def read_package(path, expected_sha=None):
    data = Path(path).read_bytes()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tgz:
        files = {}
        for member in tgz.getmembers():
            if not member.isfile(): continue
            if member.name in files: raise ValueError("duplicate member")
            files[member.name] = tgz.extractfile(member).read()
    return validate(files, expected_sha, data)

def package(build, output):
    build = Path(build)
    args_bytes = (build / "flasher_args.json").read_bytes()
    args = json.loads(args_bytes)
    flags = args["write_flash_args"]
    allowed = {"--flash_mode": {"dio", "qio", "dout", "qout"}, "--flash_freq": {"20m", "26m", "40m", "80m"},
               "--flash_size": {"detect", "16MB"}}
    if len(flags) % 2 or len(flags) != 6:
        raise ValueError("unexpected flasher flags")
    for key, value in zip(flags[::2], flags[1::2]):
        if value not in allowed.get(key, set()): raise ValueError("unexpected flasher flag")
    if set(flags[::2]) != set(allowed): raise ValueError("duplicate flasher flag")
    argv = list(flags)
    files = {"VERSION.txt": b"OpenJooki global SetVolume protocol 2\n", "esp32/flasher_args.json": args_bytes}
    for offset, name in sorted(args["flash_files"].items(), key=lambda pair: int(pair[0], 0)):
        if name.startswith("/") or ".." in Path(name).parts: raise ValueError("unsafe flash filename")
        argv.extend([offset, name])
        files["esp32/" + name] = (build / name).read_bytes()
    files["esp32/flash.sh"] = ('#!/bin/sh\nset -eu\nexec /usr/bin/python3 /usr/bin/esptool.py '
        '-p "${ESP32_UART_DEV:-/dev/ttyS0}" -b "${ESP32_UART_BAUDRATE:-1500000}" write_flash '
        + " ".join(shlex.quote(v) for v in argv) + '\n').encode()
    validate(files)
    with Path(output).open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=EPOCH) as gz, tarfile.open(fileobj=gz, mode="w") as tgz:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mtime, info.mode = len(data), EPOCH, 0o755 if name.endswith("flash.sh") else 0o644
            info.uid = info.gid = 0
            tgz.addfile(info, io.BytesIO(data))
    return read_package(output)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="action", required=True)
    c = sub.add_parser("check")
    c.add_argument("package", type=Path)
    c.add_argument("--sha256")
    b = sub.add_parser("build")
    b.add_argument("build", type=Path)
    b.add_argument("output", type=Path)
    a = p.parse_args()
    report = read_package(a.package, a.sha256) if a.action == "check" else package(a.build, a.output)
    print(json.dumps(report, indent=2))

if __name__ == "__main__": main()
