#!/usr/bin/env python3
"""Fetch the pinned public Jooki 2 sources and apply OpenJooki's additive volume protocol.
No device access. --public-sdk ports to the pinned public ESP-IDF 4.4.3 release.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request

ARCHIVE_URL = "https://jooki.com/jooki-archive-20261026.tgz"
ARCHIVE_SHA256 = "819293ee47d1b42439e50ad4d7f8f6180a6feabf2ff28595dbc45c2cc33706fc"
HERE = Path(__file__).resolve().parent
FORKS = (
    ("esp-adf", "https://github.com/espressif/esp-adf.git", "84c541bf8e7c6e8755fb2b77aa376352be6662f2", "esp-idf"),
    ("esp-idf", "https://github.com/espressif/esp-idf.git", "000d3823bb2ff697c327958e41e9dfc6b772822a", "components/esptool_py/esptool"),
)
# Espressif's v4.4.3 release commit; Wi-Fi headers and binary libraries stay paired.
PUBLIC_IDF = "6407ecb3f8d2cc07c4c230e7e64f2046af5c86f7"

def run(*args, cwd=None):
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)

def checked_download(url, digest, dest):
    dest = Path(dest)
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        part = dest.with_suffix(dest.suffix + ".part")
        request = urllib.request.Request(url, headers={"User-Agent": "OpenJooki-source-builder/1.0"})
        with urllib.request.urlopen(request, timeout=60) as src, part.open("wb") as out:
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk: break
                out.write(chunk)
        if hashlib.sha256(part.read_bytes()).hexdigest() != digest:
            part.unlink()
            raise ValueError("download checksum mismatch: " + url)
        part.replace(dest)
    if hashlib.sha256(dest.read_bytes()).hexdigest() != digest:
        raise ValueError("archive checksum mismatch: " + str(dest))
    return dest

def prepare(archive, out, sdk=False, port=False):
    archive = checked_download(ARCHIVE_URL, ARCHIVE_SHA256, archive).resolve()
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    root = out / "jooki-archive-20261026"
    inputs = [HERE / "volume.patch"]
    if port: inputs += [HERE / "sdk-port.patch", HERE / "port/sdio_tx.h", HERE / "esp-idf-v4.4.3.patch", HERE / "esp-adf-public-build.patch"]
    patch_digest = hashlib.sha256(b"".join(p.read_bytes() for p in inputs)).hexdigest()
    marker = root / ".openjooki-volume-patch"
    if root.exists():
        if not marker.exists() or marker.read_text().strip() != patch_digest:
            raise ValueError("source directory already exists with different changes; choose a fresh --out")
    else:
        run("tar", "-xzf", archive, "-C", out)
        run("git", "init", "-q", root)
        run("git", "apply", "--check", HERE / "volume.patch", cwd=root)
        run("git", "apply", HERE / "volume.patch", cwd=root)
        if port:
            run("git", "apply", "--check", HERE / "sdk-port.patch", cwd=root)
            run("git", "apply", HERE / "sdk-port.patch", cwd=root)
            shutil.copy2(HERE / "port/sdio_tx.h", root / "esp32-code/jooki_v2/main/sdio_tx.h")
        marker.write_text(patch_digest + "\n")
    if not sdk: return root
    adf = root / "build-src/esp-adf"
    for name, url, sha, exclude in FORKS:
        if port and name == "esp-idf": sha = PUBLIC_IDF
        repo = adf if name == "esp-adf" else adf / "esp-idf"
        if repo.exists() and (repo / ".git").exists():
            raise ValueError("SDK already exists; use a fresh --out for reproducible reconstruction")
        repo.mkdir(parents=True, exist_ok=True)
        run("git", "init", "-q", repo)
        run("git", "remote", "add", "origin", url, cwd=repo)
        run("git", "fetch", "--depth", "1", "origin", sha, cwd=repo)
        run("git", "checkout", "--detach", "FETCH_HEAD", cwd=repo)
        # Reconstruct ADF from the archive's patches. IDF either uses the original
        # manifest for comparison, or our reviewed patch on the pinned public release.
        # Keep Espressif's bundled esptool and the explicitly pinned DSP gitlink.
        patches = [HERE / "esp-idf-v4.4.3.patch"] if port and name == "esp-idf" else sorted((root / "patches" / name).glob("*.patch"))
        for patch in patches:
            run("git", "apply", "--index", "--whitespace=nowarn", "--exclude=" + exclude, patch, cwd=repo)
        if port and name == "esp-adf": run("git", "apply", "--index", HERE / "esp-adf-public-build.patch", cwd=repo)
        if name == "esp-adf":
            paths = ["components/esp-adf-libs", "components/esp-sr"]
        else:
            run("git", "config", "submodule.components/esptool_py/esptool.url", "https://github.com/espressif/esptool.git", cwd=repo)
            paths = []
        run("git", "submodule", "update", "--init", "--recursive", "--depth", "1", "--jobs", "4", *paths, cwd=repo)
    return root

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive", type=Path, default=HERE.parents[1] / "build/firmware/jooki-archive-20261026.tgz")
    p.add_argument("--out", type=Path, default=HERE.parents[1] / "build/firmware/source")
    modes = p.add_mutually_exclusive_group()
    modes.add_argument("--sdk", action="store_true", help="reconstruct the original, incomplete SDK for comparison")
    modes.add_argument("--public-sdk", action="store_true", help="prepare the public ESP-IDF 4.4.3 port and its SDK")
    p.add_argument("--port", action="store_true", help="prepare ported application sources only, for native tests")
    a = p.parse_args()
    if a.sdk and a.port: p.error("--sdk is the archive comparison; use --public-sdk for the ported SDK")
    print(prepare(a.archive, a.out, a.sdk or a.public_sdk, a.port or a.public_sdk))

if __name__ == "__main__": main()
