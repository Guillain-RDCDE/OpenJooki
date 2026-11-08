#!/usr/bin/env python3
"""Verify a complete downloaded playlist in new processes with networking denied."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import trial


def verify(work, uri):
    if not re.fullmatch(r"spotify:playlist:[A-Za-z0-9]{22}", uri):
        raise ValueError("Expected a Spotify playlist URI")
    if sys.platform != "darwin" or not shutil.which("sandbox-exec"):
        raise ValueError("This network-isolation check requires macOS sandbox-exec")
    source = trial.prepare(work)
    if trial.needs_build(source):
        trial.build(source)
    binary_hash = hashlib.sha256(trial.binary(source).read_bytes()).hexdigest()
    patches = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in trial.PATCHES}
    config_args = trial.private_config(work)
    config_file = work / "private/config/app.toml"
    # Use the actual configured folder, including an existing custom configuration.
    config = tomllib.loads(config_file.read_text())
    folder = Path(config["download_folder"])
    collection = folder / (hashlib.sha256(uri.encode()).hexdigest() + ".json")
    expected = json.loads(collection.read_text())
    if not isinstance(expected, list) or not expected or not all(
            isinstance(item, str) and re.fullmatch(r"spotify:track:[A-Za-z0-9]{22}", item)
            for item in expected):
        raise ValueError("Playlist manifest is empty or invalid")
    command = ["sandbox-exec", "-p", "(version 1) (allow default) (deny network*)",
               str(trial.binary(source))] + config_args + ["downloads"]
    listing = subprocess.run(command + ["list"], capture_output=True, text=True,
                             check=True, timeout=60)
    tracks = json.loads(listing.stdout)
    if any("key" in track for track in tracks):
        raise ValueError("Public track listing unexpectedly includes a key")
    by_uri = {track["uri"]: track for track in tracks}
    missing = [item for item in expected if item not in by_uri]
    if missing:
        raise ValueError(f"Playlist is incomplete: {len(missing)} missing entries")
    runs = []
    for _ in range(2):
        result = subprocess.run(command + ["verify"], capture_output=True,
                                text=True, check=True, timeout=600)
        verified = [line.split(" — ", 1)[0].removeprefix("OK ")
                    for line in result.stdout.splitlines() if line.startswith("OK ")]
        if not set(expected).issubset(verified):
            raise ValueError("Verification did not decode every playlist track")
        runs.append({"exit": result.returncode, "decoded_tracks": len(verified)})
    if hashlib.sha256(trial.binary(source).read_bytes()).hexdigest() != binary_hash:
        raise ValueError("Player binary changed during verification; rerun with a stable build")
    evidence = {"source_revision": trial.REVISION,
                "patches": patches, "binary_sha256": binary_hash,
                "network": "denied by sandbox-exec", "playlist_uri": uri,
                "playlist_entries": len(expected), "unique_tracks": len(set(expected)),
                "audio_bytes": sum(by_uri[item]["bytes"] for item in set(expected)),
                "ordered_tracks": [by_uri[item] for item in expected], "processes": runs}
    output = work / "private/playlist-offline-verification.json"
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    output.chmod(0o600)
    print(f"PASS {len(expected)} playlist entries decoded in two new processes with networking denied")
    print(f"Evidence: {output}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uri")
    parser.add_argument("--work-dir", type=Path, default=trial.DEFAULT_WORK)
    args = parser.parse_args(argv)
    try:
        verify(args.work_dir.expanduser().resolve(), args.uri)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("Spotify playlist verification failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
