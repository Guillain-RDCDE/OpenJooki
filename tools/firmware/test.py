#!/usr/bin/env python3
"""Native checks against the exact firmware sources patched from the checksum-pinned archive."""
import argparse
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
from prepare import checked_download, ARCHIVE_URL, ARCHIVE_SHA256

HERE = Path(__file__).resolve().parent

def run(*args): subprocess.run([str(a) for a in args], check=True)
def fields(proto):
    return {name: dict(re.findall(r"^\s*(?:\w+\s+)?(\w+)\s*=\s*(\d+)\s*;", body, re.M))
            for _, name, body in re.findall(r"(message|enum)\s+(\w+)\s*\{(.*?)\n\}", proto, re.S)}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--archive", type=Path, required=True)
    a = p.parse_args()
    source = a.source.resolve()
    archive = checked_download(ARCHIVE_URL, ARCHIVE_SHA256, a.archive)
    proto = source / "esp32-code/jooki_v2/api"
    with tarfile.open(archive) as tgz:
        old = tgz.extractfile("jooki-archive-20261026/esp32-code/jooki_v2/api/esp_hosted_config.proto").read().decode()
    baseline, updated = fields(old), fields((proto / "esp_hosted_config.proto").read_text())
    for message, pairs in baseline.items():
        for name, number in pairs.items():
            assert updated[message][name] == number, (message, name, "wire number changed")
    assert updated["EspHostedConfigMsgType"]["TypeCmdSetVolume"] == "86"
    assert updated["EspHostedConfigPayload"]["cmd_set_volume"] == "92"
    print("PASS every existing protobuf message number and field tag is unchanged", flush=True)
    ctrl = source / "ml-yocto-jooki/sw/controllers/esp32_ctrl"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        run("cc", "-std=c99", "-Wall", "-Wextra", "-Werror", "-I" + str(source / "esp32-code/jooki_v2/main"), "-I" + str(ctrl), HERE / "tests/volume.c", "-o", out / "volume")
        run(out / "volume")
        run("protoc-c", "-I" + str(proto), "--c_out=" + str(out), proto / "esp_hosted_config.proto")
        run("cc", "-D_DEFAULT_SOURCE", "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections", "-fsanitize=address,undefined", "-g", "-I" + str(ctrl), "-I" + str(out), HERE / "tests/protocol.c", ctrl / "commands.c", out / "esp_hosted_config.pb-c.c", "-lprotobuf-c", "-o", out / "protocol")
        run(out / "protocol")

if __name__ == "__main__": main()
