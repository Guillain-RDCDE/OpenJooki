#!/usr/bin/env python3
"""Inventory Spotify offline interfaces in the pinned public Jooki source archive.

Reads local files only; does not extract the archive or contact/change a Jooki.
Declarations and error names are evidence to review, never proof of SDK support.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile


ARCHIVE_URL = "https://jooki.com/jooki-archive-20261026.tgz"
ARCHIVE_SHA256 = "819293ee47d1b42439e50ad4d7f8f6180a6feabf2ff28595dbc45c2cc33706fc"
PREFIX = "jooki-archive-20261026/ml-yocto-jooki/sw/controllers/spotify_ctrl/"
FILES = ("spotify_ctrl.c", "spotify_embedded.h", "CMakeLists.txt", "README.md", "ml-j2000/machine.h")
LIBRARY = "ml-j2000/libspotify_embedded_static.a"
C_TOKENS = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
OFFLINE_NAME = re.compile(r"offline|prefetch|storage|cache", re.I)


def c_code(text, *, keep_strings=False):
    """Remove comments (and optionally literals), retaining line boundaries."""
    def replace(match):
        token = match.group()
        if keep_strings and token[0] in "\"'":
            return token
        return "\n" * token.count("\n") or " "

    return C_TOKENS.sub(replace, text)


def required_match(pattern, text, field):
    match = re.search(pattern, text, re.M)
    if match is None:
        raise ValueError("Cannot identify " + field)
    return match.group(1)


def inventory(sources, library_present):
    """Collect facts without inferring feature availability from their names."""
    controller = c_code(sources["spotify_ctrl.c"], keep_strings=True)
    header = c_code(sources["spotify_embedded.h"])
    declarations = re.findall(r"^SP_EMB_PUBLIC\b[^;]*;", header, re.M)
    functions = sorted({name for declaration in declarations
                        for name in re.findall(r"\b(Sp\w+)\s*\(", declaration)})
    callbacks = re.findall(r"\(\s*\*\s*(Sp\w+)\s*\)", header)
    errors = re.findall(r"\b(kSp\w+)\s*=", header)
    calls = sorted(set(re.findall(r"\b(Sp\w+)\s*\(", c_code(sources["spotify_ctrl.c"]))))
    topics = re.findall(r'\{\s*"(/j/spotify/output/[^"\n]+)"\s*,', controller)

    def candidates(names):
        return sorted(name for name in names if OFFLINE_NAME.search(name))

    return {
        "offline_support": "unresolved",
        "scope": "Published source inventory; installed SDK build and device enablement unverified",
        "controller": {
            "esdk_version_from_source": required_match(r'^#define\s+ESDK_VERSION\s+"([^"\n]+)"', controller, "eSDK version"),
            "header_api_version": int(required_match(r"^#define\s+SP_API_VERSION\s+(\d+)", header, "API version")),
            "model": required_match(r'^#define\s+MODEL_NAME\s+"([^"\n]+)"', c_code(sources["ml-j2000/machine.h"], keep_strings=True), "model"),
            "product_id_from_source": int(required_match(r"conf\.product_id\s*=\s*(\d+)", controller, "product ID")),
            "required_sdk_library": LIBRARY,
            "sdk_library_in_archive": library_present,
            "mqtt_commands": topics,
            "sdk_function_calls": calls,
            "offline_related_sdk_calls": candidates(calls),
        },
        "header": {
            "public_function_count": len(functions),
            "offline_related_function_declarations": candidates(functions),
            "offline_related_callback_types": candidates(callbacks),
            "offline_related_error_constants": candidates(errors),
        },
        "unverified": [
            "Installed SDK version, compiled features and storage interfaces",
            "Offline enablement for the actual client/product/device/account",
            "Rebuilding and linking spotify_ctrl with the required licensed SDK",
            "Complete playlist playback and seeking without Internet after a cold restart",
        ],
    }


def audit(archive):
    checksum = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(chunk)
    digest = checksum.hexdigest()
    if digest != ARCHIVE_SHA256:
        raise ValueError("Source archive SHA-256 mismatch; use the pinned official archive")

    sources, hashes = {}, {}
    with tarfile.open(archive, "r:gz") as bundle:
        for name in FILES:
            member = bundle.getmember(PREFIX + name)
            if not member.isfile():
                raise ValueError("Expected a regular source file: " + name)
            with bundle.extractfile(member) as source:
                data = source.read()
            sources[name] = data.decode("utf-8")
            hashes[name] = hashlib.sha256(data).hexdigest()
        library = next((m for m in bundle.getmembers() if m.name == PREFIX + LIBRARY), None)
        library_present = library is not None and library.isfile()

    result = inventory(sources, library_present)
    result["archive"] = {"url": ARCHIVE_URL, "sha256": digest}
    result["source_sha256"] = hashes
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="local jooki-archive-20261026.tgz (not downloaded automatically)")
    args = parser.parse_args(argv)
    try:
        result = audit(args.archive)
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print("Spotify source audit failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
