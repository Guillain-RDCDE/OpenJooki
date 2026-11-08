#!/usr/bin/env python3
"""Build and try the pinned experimental Spotify offline player on this computer."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPOSITORY = "https://github.com/CormAlan/spotify-player-offline-mode.git"
REVISION = "cd47e7594b2f564c52a07751c6c4b0f27b26af06"
FEATURES = "rodio-backend,rustls-tls"
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORK = ROOT / "build/spotify-offline/trial"
AUTH_PATCH = Path(__file__).with_name("auth-redirect.patch")
BOUNDED_PATCH = Path(__file__).with_name("bounded-audio.patch")
PATCHES = (AUTH_PATCH, BOUNDED_PATCH)


def run(command, cwd=None, capture=False, extra_env=None):
    env = os.environ.copy()
    env.setdefault("CARGO_HTTP_MULTIPLEXING", "false")
    env.setdefault("CARGO_BUILD_JOBS", "2")
    env.setdefault("CARGO_PROFILE_DEV_DEBUG", "0")
    env.setdefault("CARGO_PROFILE_TEST_DEBUG", "0")
    env.setdefault("CARGO_INCREMENTAL", "0")
    env.update(extra_env or {})
    return subprocess.run(command, cwd=cwd, env=env, check=True,
                          text=True, capture_output=capture)


def diff_chunks(diff):
    return tuple(sorted(chunk.rstrip("\n") for chunk in diff.split("diff --git ")[1:]))


def prepare(work, source_name="source", patch_files=PATCHES):
    source = work / source_name
    if not source.exists():
        source.mkdir(parents=True)
        run(["git", "init", "-q", str(source)])
        run(["git", "remote", "add", "origin", REPOSITORY], cwd=source)
        run(["git", "fetch", "--depth", "1", "origin", REVISION], cwd=source)
        run(["git", "checkout", "--detach", "FETCH_HEAD"], cwd=source)
    head = run(["git", "rev-parse", "HEAD"], cwd=source, capture=True).stdout.strip()
    if head != REVISION:
        raise ValueError("Checkout has another revision; choose a fresh --work-dir")
    status = run(["git", "status", "--porcelain", "--untracked-files=all"],
                 cwd=source, capture=True).stdout
    patches = [patch.read_text() for patch in patch_files]
    actual = run(["git", "diff", "--no-color", "--no-ext-diff", "--binary",
                  "--abbrev=7", "--unified=0", "HEAD"],
                 cwd=source, capture=True).stdout
    staged = run(["git", "diff", "--cached", "--name-only"],
                 cwd=source, capture=True).stdout
    if staged or any(line.startswith("??") for line in status.splitlines()):
        raise ValueError("Checkout has local changes; choose a fresh --work-dir")
    applied = next((count for count in range(len(patches) + 1)
                    if diff_chunks(actual) == diff_chunks("".join(patches[:count]))), None)
    if applied is None:
        raise ValueError("Checkout differs from the reviewed trial patches; choose a fresh --work-dir")
    for patch in patch_files[applied:]:
        run(["git", "apply", "--check", "--unidiff-zero", str(patch)], cwd=source)
        run(["git", "apply", "--unidiff-zero", str(patch)], cwd=source)
    return source


def binary(source):
    name = "spotify_player.exe" if os.name == "nt" else "spotify_player"
    return source / "target/debug" / name


def build(source):
    fingerprint = profile_hash()
    run(["cargo", "build", "--locked", "--no-default-features", "--features", FEATURES],
        cwd=source, extra_env={"CARGO_TARGET_DIR": str(source / "target")})
    if not binary(source).is_file():
        raise ValueError("Expected native binary missing; use the default CARGO_TARGET_DIR")
    if profile_hash() != fingerprint:
        raise ValueError("Trial patches changed during the build; rerun with a stable profile")
    (source / "target/openjooki-profile.sha256").write_text(fingerprint)


def profile_hash():
    return hashlib.sha256(REVISION.encode() + FEATURES.encode()
                          + b"".join(patch.read_bytes() for patch in PATCHES)).hexdigest()


def needs_build(source):
    stamp = source / "target/openjooki-profile.sha256"
    return not binary(source).is_file() or not stamp.exists() or stamp.read_text() != profile_hash()


def test(source):
    run(["cargo", "test", "--locked", "--no-default-features", "--features", FEATURES,
         "downloads::", "--", "--nocapture"], cwd=source,
        extra_env={"CARGO_TARGET_DIR": str(source / "target")})


def private_config(work):
    private = work / "private"
    for path in (private, private / "config", private / "cache", private / "downloads"):
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.chmod(0o700)
    app = private / "config/app.toml"
    if not app.exists():
        # JSON strings are also valid TOML basic strings, including Windows paths.
        text = "download_folder = " + json.dumps(str(private / "downloads"))
        text += "\n[device]\nbitrate = 96\nvolume = 20\n"
        with app.open("x") as out:
            out.write(text)
        app.chmod(0o600)
    return ["-c", str(private / "config"), "-C", str(private / "cache")]


def main(argv=None):
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=DEFAULT_WORK)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "build", "test", "check"):
        commands.add_parser(name)
    player = commands.add_parser("run", help="run the player with separate private configuration")
    player.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    work = args.work_dir.expanduser().resolve()
    try:
        source = prepare(work)
        if args.command in ("build", "check"):
            build(source)
        if args.command in ("test", "check"):
            test(source)
        if args.command == "run":
            if needs_build(source):
                build(source)
            extra = args.args[1:] if args.args[:1] == ["--"] else args.args
            run([str(binary(source))] + private_config(work) + extra)
        return 0
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Spotify offline trial failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
