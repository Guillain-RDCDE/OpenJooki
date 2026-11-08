#!/usr/bin/env python3
"""Decode synthetic test audio after process restarts with macOS networking denied."""
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import trial


def fixture(source, folder):
    config, cache, downloads = (folder / name for name in ("config", "cache", "downloads"))
    for path in (config, cache, downloads):
        path.mkdir(mode=0o700)
    audio = source / "spotify_player/src/downloads/testdata/silence.ogg"
    plain = bytes(167) + audio.read_bytes()
    # Invented fixture key and generated silence; no Spotify account/content involved.
    key = bytes([42]) * 16
    encrypted = subprocess.run(
        ["openssl", "enc", "-aes-128-ctr", "-nosalt", "-K", key.hex(),
         "-iv", "72e067fbddcbcf77ebe8bc643f630d93"],
        input=plain, capture_output=True, check=True,
    ).stdout
    uri = "spotify:track:" + "0" * 22
    header = json.dumps({
        "version": 1, "uri": uri, "name": "OpenJooki synthetic silence",
        "artists": ["Local test fixture"], "album": "Offline trial",
        "cover_url": None, "duration_ms": 120, "key": list(key),
        "bytes": len(encrypted), "sha256": hashlib.sha256(encrypted).hexdigest(),
    }, separators=(",", ":")).encode()
    target = downloads / ("0" * 22 + ".spdl")
    target.write_bytes(b"SPDL0001" + struct.pack("<I", len(header)) + header + encrypted)
    target.chmod(0o600)
    (config / "app.toml").write_text(
        "download_folder = " + json.dumps(str(downloads)) + "\n[device]\nvolume = 0\n"
    )
    return config, cache, uri


def smoke(work):
    if sys.platform != "darwin" or not shutil.which("sandbox-exec"):
        raise ValueError("This network-isolation smoke requires macOS sandbox-exec")
    if not shutil.which("openssl"):
        raise ValueError("The synthetic fixture requires the openssl command")
    source = trial.prepare(work)
    if trial.needs_build(source):
        trial.build(source)
    results = []
    with tempfile.TemporaryDirectory(prefix="offline-smoke-", dir=work) as temp:
        config, cache, uri = fixture(source, Path(temp))
        command = ["sandbox-exec", "-p", "(version 1) (allow default) (deny network*)",
                   str(trial.binary(source)), "-c", str(config), "-C", str(cache)]
        for args in (["downloads", "list"], ["downloads", "verify"], ["downloads", "verify"]):
            process = subprocess.run(command + args, capture_output=True, text=True, timeout=30, check=False)
            if process.returncode:
                raise ValueError("Offline command failed: " + process.stderr.strip())
            if args[-1] == "list":
                tracks = json.loads(process.stdout)
                if len(tracks) != 1 or tracks[0]["uri"] != uri or "key" in tracks[0]:
                    raise ValueError("Unexpected public fixture listing")
            elif "decoded audio packets" not in process.stdout:
                raise ValueError("Verification did not report decoded audio")
            results.append({"command": args, "exit": process.returncode, "stdout": process.stdout})
    evidence = {"source_revision": trial.REVISION, "network": "denied by sandbox-exec",
                "binary_sha256": hashlib.sha256(trial.binary(source).read_bytes()).hexdigest(),
                "patches": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in trial.PATCHES},
                "audio": "synthetic silence, no Spotify content", "processes": results}
    (work / "native-offline-smoke.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("PASS synthetic audio decoded in two new processes with networking denied")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=trial.DEFAULT_WORK)
    args = parser.parse_args(argv)
    try:
        smoke(args.work_dir.expanduser().resolve())
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("Spotify offline smoke failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
