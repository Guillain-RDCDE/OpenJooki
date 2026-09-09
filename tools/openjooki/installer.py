#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenJooki — engine for the SAFE installation of a firmware on a Jooki v2.

Anti-brick principle (identical to the rest of OpenJooki):
  * We NEVER write to the active partition, nor to the bootloader/factory.
  * The firmware is written to the SPARE partition (A/B).
  * We verify the transfer BIT FOR BIT (source hash == read-back hash).
  * We check that it is a bootable system before activating.
  * Activation arms the U-Boot rollback: if it does not boot, the device
    reverts on its own to the previous version.
Standard library only.
"""
__version__ = "0.2.1"
import os, sys, gzip, struct, hashlib, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jooki

CHUNK = 1024 * 1024


class InstallError(Exception):
    pass


def _ssh_base(host):
    return ["ssh", "-p", jooki.SSH_PORT, "-i", jooki.KEY] + jooki.SSH_OPTS + ["root@" + host]


def _partition_bytes(host, s):
    o = jooki.ssh(host, "cat /sys/class/block/mmcblk0p%s/size 2>/dev/null" % s).stdout.strip()
    return int(o) * 512 if o.isdigit() else 0


def _remote_hash_tool(host):
    o = jooki.ssh(host, "which sha256sum; which md5sum").stdout
    if "sha256sum" in o:
        return "sha256sum", "sha256"
    if "md5sum" in o:
        return "md5sum", "md5"
    raise InstallError("No verification tool (sha256sum/md5sum) on the device.")


def _remote_hash_region(host, path, total, htool, timeout=900):
    """Hash of the first `total` bytes of `path` (device or file) on the device.
       Does NOT use `head -c` (absent from this busybox): dd bs=512 + exact remainder in bs=1."""
    b512 = total // 512
    rem = total % 512
    cmd = "dd if=%s bs=512 count=%d 2>/dev/null" % (path, b512)
    if rem:
        cmd += "; dd if=%s bs=1 skip=%d count=%d 2>/dev/null" % (path, b512 * 512, rem)
    r = jooki.ssh(host, "{ %s; } | %s" % (cmd, htool), timeout=timeout)
    out = (r.stdout or "").strip()
    return out.split()[0] if out else ""


def _is_gz(path):
    with open(path, "rb") as f:
        return f.read(2) == b"\x1f\x8b"


def _open_maybe_gz(path):
    return gzip.open(path, "rb") if _is_gz(path) else open(path, "rb")


def _uncompressed_size(path):
    if _is_gz(path):
        with open(path, "rb") as f:
            f.seek(-4, 2)
            return struct.unpack("<I", f.read(4))[0]  # ISIZE mod 2^32 (< 4 GB)
    return os.path.getsize(path)


def _local_hash(path, algo):
    """Hash of the UNCOMPRESSED bytes of path (computed locally, no network)."""
    h = hashlib.new(algo)
    with _open_maybe_gz(path) as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def human(n):
    n = float(n)
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return ("%d %s" % (n, u)) if u == "B" else ("%.1f %s" % (n, u))
        n /= 1024.0
    return "%.1f TB" % n


def install_firmware(host, image_path, on_step=None, on_progress=None, do_switch=True):
    """Install image_path on the Jooki spare partition, safely.
       on_step(str): step message; on_progress(int 0..100): progress.
       Returns a dict {ok, switched, active, ...}. Raises InstallError on refusal/failure
       BEFORE any activation (in that case the Jooki has not changed)."""
    def step(m):
        (on_step or jooki.log)(m)
    def prog(p):
        if on_progress:
            on_progress(max(0, min(100, int(p))))

    step("Secure connection to the device…"); prog(1)
    if not jooki.is_jooki(host):
        raise InstallError("Jooki not found on the network.")
    if not jooki.ensure_ssh(host):
        raise InstallError("Secure access impossible.")
    a = jooki._boot_part(host)
    if a not in ("2", "3"):
        raise InstallError("Unexpected partition state (%r)." % a)
    s = jooki._spare(a); sdev = "/dev/mmcblk0p" + s
    psize = _partition_bytes(host, s)
    if psize <= 0:
        raise InstallError("Spare partition size unreadable.")

    step("Analyzing the firmware file…"); prog(2)
    if not os.path.isfile(image_path):
        raise InstallError("File not found: %s" % image_path)
    htool, halgo = _remote_hash_tool(host)
    total = _uncompressed_size(image_path)
    if total <= 0:
        raise InstallError("File unreadable or empty.")
    if total > psize:
        raise InstallError("Firmware too large (%s) for the spare partition (%s)."
                           % (human(total), human(psize)))
    if total < 4 * 1024 * 1024:
        raise InstallError("File too small for a Jooki firmware (%s)." % human(total))

    # Reference hash: computed LOCALLY on the uncompressed bytes
    # (what must end up on the partition), without network.
    step("Computing the firmware hash…"); prog(3)
    src_hash = _local_hash(image_path, halgo)

    step("Safety backup of your content…"); prog(5)
    jooki.quick_backup(host)

    # Make sure the spare partition is not mounted before writing.
    jooki.ssh(host, "umount /mnt/spchk /mnt/p2patch 2>/dev/null; true")

    # Transfer to the SPARE. If the image is compressed (.gz) and the device
    # can decompress, we send ONLY the compressed bytes (much lighter on the
    # network) and the device decompresses while writing. Otherwise, send uncompressed.
    gz = _is_gz(image_path)
    dev_gunzip = gz and ("gzip" in jooki.ssh(host, "which gzip gunzip").stdout)
    if dev_gunzip:
        remote = "gzip -dc | dd of=%s bs=1M 2>/dev/null" % sdev
        feeder = open(image_path, "rb")            # COMPRESSED bytes
        wire_total = os.path.getsize(image_path)
        step("Compressed transfer to spare partition p%s (do not unplug)…" % s)
    else:
        remote = "dd of=%s bs=1M 2>/dev/null" % sdev
        feeder = _open_maybe_gz(image_path)        # decompressed locally
        wire_total = total
        step("Transfer to spare partition p%s (do not unplug)…" % s)
    proc = subprocess.Popen(_ssh_base(host) + [remote], stdin=subprocess.PIPE)
    sent = 0
    try:
        while True:
            b = feeder.read(CHUNK)
            if not b:
                break
            proc.stdin.write(b)
            sent += len(b); prog(6 + sent * 54.0 / max(1, wire_total))
    finally:
        feeder.close()
        try:
            proc.stdin.close()
        except Exception:
            pass
    rc = proc.wait()
    if rc != 0:
        raise InstallError("Transfer interrupted (code %d). The current version is intact." % rc)
    jooki.ssh(host, "sync", timeout=120)

    # BIT-FOR-BIT check: read back exactly `total` bytes of the partition and compare.
    step("Bit-for-bit verification of the transfer (%s)…" % halgo); prog(62)
    dev_hash = _remote_hash_region(host, sdev, total, htool)
    if dev_hash != src_hash:
        raise InstallError("Verification failed: written data differs (%s… != %s…). "
                           "Nothing was activated, your Jooki has not changed."
                           % (dev_hash[:12], src_hash[:12]))
    step("Transfer identical bit for bit ✓"); prog(72)

    # Check: is this a bootable Jooki system?
    step("Checking the firmware (bootable system)…"); prog(76)
    chk = jooki.ssh(host, "mkdir -p /mnt/spchk; mount -o ro %s /mnt/spchk 2>&1 && "
                    "{ echo MOUNT_OK; ls /mnt/spchk/boot/uImage 2>&1; "
                    "echo ART=$(cat /mnt/spchk/etc/mender/artifact_info 2>/dev/null); }; "
                    "umount /mnt/spchk 2>/dev/null" % sdev, timeout=90).stdout
    if "MOUNT_OK" not in chk or "uImage" not in chk:
        raise InstallError("This file is not a bootable Jooki firmware "
                           "(no kernel detected). Nothing was activated.")

    if not do_switch:
        step("Firmware written and verified on the spare partition (activation not requested)."); prog(100)
        return {"ok": True, "switched": False, "hash": src_hash, "active": a, "spare": s}

    # Activation with U-Boot rollback armed (see jooki.ab_switch).
    step("Activation + test (reboot ~2 min, do not unplug)…"); prog(80)
    rc = jooki.ab_switch(host, s)
    if rc == 0:
        step("Firmware active and working ✓"); prog(100)
        return {"ok": True, "switched": True, "hash": src_hash, "active": s, "previous": a}
    step("The new version did not boot: automatic return to the previous version."); prog(100)
    return {"ok": False, "switched": False, "hash": src_hash, "active": a, "spare": s, "reason": "boot"}


def dump_partition(host, part, out_path, use_gzip=True, on_progress=None):
    """Dump partition p<part> to a local file (gzip on the device side to
       reduce the transfer). Used to build a real, bootable test image."""
    dev = "/dev/mmcblk0p" + part
    remote = "dd if=%s bs=1M 2>/dev/null" % dev
    if use_gzip and "gzip" in jooki.ssh(host, "which gzip").stdout:
        remote += " | gzip -1"
    else:
        out_path = out_path[:-3] if out_path.endswith(".gz") else out_path
    with open(out_path, "wb") as f:
        proc = subprocess.Popen(_ssh_base(host) + [remote], stdout=f)
        rc = proc.wait()
    return rc, out_path


def selftest_transfer(host, size_mb=8, on_step=None):
    """Plumbing test WITHOUT touching the partitions: sends a random file
       to /data, reads it back, compares the hash. Safe and fast."""
    step = on_step or jooki.log
    import tempfile, os as _os
    if not jooki.ensure_ssh(host):
        raise InstallError("SSH KO")
    htool, halgo = _remote_hash_tool(host)
    total = size_mb * CHUNK + 777  # size NOT a multiple of 1 MB -> tests the exact remainder
    data = _os.urandom(total)
    src_hash = hashlib.new(halgo, data).hexdigest()
    step("selftest: sending %d bytes to /data/ojtest.bin…" % total)
    proc = subprocess.Popen(_ssh_base(host) + ["dd of=/data/ojtest.bin bs=1M 2>/dev/null"],
                            stdin=subprocess.PIPE)
    proc.stdin.write(data); proc.stdin.close()
    if proc.wait() != 0:
        raise InstallError("selftest: transfer KO")
    jooki.ssh(host, "sync")
    full_hash = (jooki.ssh(host, "%s /data/ojtest.bin" % htool, timeout=120).stdout or "").strip().split()[0]
    region_hash = _remote_hash_region(host, "/data/ojtest.bin", total, htool, timeout=180)
    jooki.ssh(host, "rm -f /data/ojtest.bin")
    ok = (full_hash == src_hash) and (region_hash == src_hash)
    step("selftest: %s | file=%s… region=%s… src=%s…"
         % ("OK bit-for-bit" if ok else "FAILED", full_hash[:10], region_hash[:10], src_hash[:10]))
    return ok


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(prog="openjooki-install")
    ap.add_argument("--host", default=jooki.DEFAULT_HOST)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--no-switch", action="store_true", help="writes+verifies but does not activate")
    ap.add_argument("image", nargs="?")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(0 if selftest_transfer(args.host) else 1)
    if not args.image:
        ap.error("specify a firmware file (or --selftest)")
    res = install_firmware(args.host, args.image, do_switch=not args.no_switch)
    print("RESULT:", res)
    sys.exit(0 if res.get("ok") else 2)
