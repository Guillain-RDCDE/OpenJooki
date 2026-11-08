#!/usr/bin/env python3
"""Build the trial for Jooki using a prepared musl/ALSA cross-toolchain."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import trial

HERE = Path(__file__).resolve().parent
PATCHES = trial.PATCHES + (HERE / "mips-tls.patch",)
TARGET = "mipsel-jooki-linux-musl"


def build(work, image):
    source = trial.prepare(work, "source-mips", PATCHES)
    for path in (work / "sysroot/usr/lib/libasound.a", work / "gcc-unwind/libunwind.a"):
        if not path.is_file():
            raise ValueError(f"Missing {path}; prepare the cross-toolchain as described in README.md")
    image_id = trial.run(["docker", "image", "inspect", "--format", "{{.Id}}", image],
                         capture=True).stdout.strip()
    rust_root = Path(trial.run(["rustc", "--print", "sysroot"], capture=True).stdout.strip())
    if not (rust_root / "lib/rustlib/src/rust/library/Cargo.toml").is_file():
        raise ValueError("The host compiler's matching rust-src component is required")
    registry = Path(os.environ.get("CARGO_HOME", str(Path.home() / ".cargo"))) / "registry"
    (work / "tmp").mkdir(exist_ok=True)
    shutil.copyfile(HERE / (TARGET + ".json"), work / (TARGET + ".json"))
    config = {"image": image_id, "mounts": [str(work), str(registry), str(rust_root)]}
    (work / "cross-toolchain.json").write_text(json.dumps(config))
    wrapper = '''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
base = Path(__file__).resolve().parent
config = json.loads((base / "cross-toolchain.json").read_text())
tools = {"cc": "/opt/oj-mips/bin/musl-gcc", "ar": "/usr/bin/mipsel-linux-gnu-ar",
         "ranlib": "/usr/bin/mipsel-linux-gnu-ranlib"}
tool = Path(__file__).stem.removeprefix("mips-musl-")
command = ["docker", "run", "--rm", "-i", "--network", "none", "--platform", "linux/amd64"]
for index, path in enumerate(config["mounts"]):
    command += ["-v", path + ":" + path + ("" if index == 0 else ":ro")]
command += ["-w", os.getcwd(), config["image"], tools[tool]] + sys.argv[1:]
sys.exit(subprocess.run(command).returncode)
'''
    for name in ("cc", "ar", "ranlib"):
        path = work / ("mips-musl-" + name + ".py")
        path.write_text(wrapper)
        path.chmod(0o700)
    env = os.environ.copy()
    env.update({
        "RUSTC_BOOTSTRAP": "1", "CARGO_HTTP_MULTIPLEXING": "false", "CARGO_BUILD_JOBS": "2",
        "CARGO_PROFILE_RELEASE_DEBUG": "0", "CARGO_PROFILE_RELEASE_PANIC": "abort",
        "CARGO_PROFILE_RELEASE_STRIP": "symbols", "CARGO_INCREMENTAL": "0",
        "CARGO_TARGET_DIR": str(work / "cross-smoke/target"),
        "CARGO_TARGET_MIPSEL_JOOKI_LINUX_MUSL_LINKER": str(work / "mips-musl-cc.py"),
        "CC_mipsel_jooki_linux_musl": str(work / "mips-musl-cc.py"),
        "AR_mipsel_jooki_linux_musl": str(work / "mips-musl-ar.py"),
        "RANLIB_mipsel_jooki_linux_musl": str(work / "mips-musl-ranlib.py"),
        "PKG_CONFIG_ALLOW_CROSS": "1", "PKG_CONFIG_LIBDIR": str(work / "sysroot/usr/lib/pkgconfig"),
        "PKG_CONFIG_SYSROOT_DIR": str(work / "sysroot"), "ALSA_STATIC": "1",
        "TMPDIR": str(work / "tmp"),
        "RUSTFLAGS": "-Z unstable-options -C link-self-contained=no -C relocation-model=static -L native="
                     + str(work / "gcc-unwind"),
    })
    subprocess.run(["cargo", "-Z", "json-target-spec", "-Z", "build-std=std,panic_abort",
                    "-Z", "build-std-features=compiler-builtins-mem", "build", "--locked", "--release",
                    "--target", str(work / (TARGET + ".json")), "--no-default-features",
                    "--features", "alsa-backend,rustls-tls"], cwd=source, env=env, check=True)
    binary = work / "cross-smoke/target" / TARGET / "release/spotify_player"
    manifest = {"source_revision": trial.REVISION, "compiler_image": image_id,
                "rustc": trial.run(["rustc", "--version"], capture=True).stdout.strip(),
                "patches": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in PATCHES},
                "binary_bytes": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    (work / "mips-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(binary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=trial.DEFAULT_WORK)
    parser.add_argument("--image", default="openjooki-firmware-port-tools:local")
    args = parser.parse_args(argv)
    try:
        build(args.work_dir.expanduser().resolve(), args.image)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("Jooki cross-build failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
