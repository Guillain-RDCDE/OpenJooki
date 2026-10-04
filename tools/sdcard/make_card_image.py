#!/usr/bin/env python3
"""OpenJooki - build the "new card" image: a complete Jooki v2 SD card, made from scratch,
with no family data on it. Linux, as root (WSL is fine): e2fsprogs, dosfstools, util-linux, gdisk.

  sudo python3 make_card_image.py --boot boot.bin --factory p1.img \\
       --rootfs openjooki-firmware-2.0.4.img.gz --version 2.0.4 --out build/openjooki-sdcard-2.0.4.img \\
       [--forget jooki2-0426E8 --forget A8:EE:C6:04:26:E8]

  boot.bin   the first 49152 sectors (24 MiB) of a Jooki's card: partition table, bootloader and
             its settings; read on a Jooki with  dd if=/dev/mmcblk0 bs=512 count=49152
  p1.img     the factory partition of a Jooki's card (256 MiB):  cat /dev/mmcblk0p1
  rootfs     the OpenJooki release image (goes on p2 AND p3, so the bootloader always has a way back)
  --forget   strings that must not appear anywhere in the result (the name and MAC of the Jooki the
             pieces came from): the build fails if one is found

The card has the Jooki's own layout, 7 partitions on a GPT (see tools/sdcard/README.md):
  p1 factory (as read)   p2, p3 system A/B (the release)   p4 swap   p5 data (generic files only)
  p6 config (FAT16 "config", empty)   p7 content (empty, 128 MiB: the Jooki grows it at the first start)
The image stops right after p7 (about 2.4 GB), so it fits any card of 4 GB or more; the SD tool
grows the content partition to the end of the card when it writes it (like for a bigger card).
Written next to the image: <out>.gz and sdcard.json (name, sizes, SHA-256 of both), the two files
to attach to the GitHub release.
"""
import argparse, hashlib, json, os, shutil, struct, subprocess, sys, tempfile, time, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jooki_sd  # noqa: E402  (the GPT code the SD tool itself uses)

SECTOR = 512
BOOT_SECTORS = 49152                         # p1 starts here on a Jooki card (24 MiB)
PARTS = {                                    # first, last sector, as on every Jooki v2 card
    1: (49152, 573439), 2: (573440, 2080767), 3: (2080768, 3588095), 4: (3588096, 3719167),
    5: (3719168, 3981311), 6: (3981312, 4505599)}
CONTENT_START = 4505600
CONTENT_SECTORS = 262144                     # 128 MiB, grown to the card by the tool then by the Jooki
TOTAL = CONTENT_START + CONTENT_SECTORS + 34  # + backup GPT
ENV_OFFSETS, ENV_SIZE = (0x800000, 0x1000000), 0x8000   # U-Boot settings, two copies (fw_env.config)
# ext4 as the Jooki's own partitions (a 2018 e2fsprogs on the device: nothing newer)
EXT4_FEATURES = ("has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,"
                 "large_file,huge_file,dir_nlink,extra_isize,^metadata_csum,^64bit,^orphan_file,^metadata_csum_seed")


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit("%s failed:\n%s%s" % (cmd[0], r.stdout, r.stderr))
    return r.stdout


def sha256_file(path, offset=0, length=None):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        f.seek(offset)
        left = length if length is not None else os.path.getsize(path) - offset
        while left > 0:
            b = f.read(min(4 << 20, left))
            if not b:
                raise SystemExit("short read in " + path)
            h.update(b); left -= len(b)
    return h.hexdigest()


def env_vars(blob):
    """A U-Boot environment copy (CRC32, flag byte, NUL-separated vars) -> (flag, ordered pairs), or raise."""
    crc, = struct.unpack_from("<I", blob, 0)
    if zlib.crc32(blob[5:]) != crc:
        raise SystemExit("the bootloader settings in boot.bin have a bad checksum")
    text = blob[5:].split(b"\0\0", 1)[0]
    return blob[4], [tuple(kv.decode("latin-1").split("=", 1)) for kv in text.split(b"\0") if b"=" in kv]


# a new card starts at rest: no update pending, no boot counted, no factory reset asked,
# system A (p2) first; p2 and p3 are identical anyway
ENV_AT_REST = {"upgrade_available": "0", "bootcount": "0", "factory_reset": "0", "dfu_active": "0",
               "mender_boot_part": "2", "mender_boot_part_hex": "2"}


def env_blob(pairs):
    """Ordered pairs -> one environment copy (CRC32, flag 1, vars, zero-padded to ENV_SIZE)."""
    d = dict(pairs); d.update(ENV_AT_REST)
    data = b"\0".join(("%s=%s" % (k, d[k])).encode("latin-1") for k, _ in pairs) + b"\0\0"
    if len(data) > ENV_SIZE - 5:
        raise SystemExit("bootloader settings too long")
    data = data.ljust(ENV_SIZE - 5, b"\0")
    return struct.pack("<I", zlib.crc32(data)) + b"\x01" + data


def check_boot(boot):
    """Checks boot.bin and returns (GPT head, the settings copy to write on the new card)."""
    if os.path.getsize(boot) != BOOT_SECTORS * SECTOR:
        raise SystemExit("boot.bin must be exactly %d bytes (%d sectors)" % (BOOT_SECTORS * SECTOR, BOOT_SECTORS))
    with open(boot, "rb") as f:
        head = f.read(34 * SECTOR)
        f.seek(34 * SECTOR); spl = f.read(16)
        envs = []
        for off in ENV_OFFSETS:
            f.seek(off); envs.append(env_vars(f.read(ENV_SIZE)))
    jooki_sd.check_jooki(head)
    for i, (s, e) in PARTS.items():
        ent = 1024 + (i - 1) * 128
        if struct.unpack_from("<QQ", head, ent + 32) != (s, e):
            raise SystemExit("partition %d of boot.bin is not at the sectors of a Jooki card" % i)
    if struct.unpack_from("<Q", head, 1024 + 6 * 128 + 32)[0] != CONTENT_START:
        raise SystemExit("the content partition of boot.bin does not start at sector %d" % CONTENT_START)
    if spl[:4] != b"LPSM":
        raise SystemExit("no bootloader at sector 34 of boot.bin")
    # the copy the bootloader itself uses: the higher flag (both checksums are already known good)
    flag, pairs = max(envs, key=lambda fp: fp[0])
    d = dict(pairs)
    for k in ("bootcmd", "mender_boot_part", "mender_setup", "mender_rootfs_part_a", "mender_rootfs_part_b", "mender_altbootcmd"):
        if k not in d:
            raise SystemExit("bootloader settings without " + k)
    if (d["mender_rootfs_part_a"], d["mender_rootfs_part_b"]) != ("2", "3"):
        raise SystemExit("unexpected system partitions in the bootloader settings")
    blob = env_blob(pairs)
    f2, p2 = env_vars(blob)                                  # read back through the same parser
    if f2 != 1 or dict(p2) != dict(dict(pairs), **ENV_AT_REST):
        raise SystemExit("bootloader settings: rewrite mismatch")
    print("boot.bin: Jooki layout, bootloader at sector 34, settings read (copy with flag %d, was booting p%s) and put at rest: boots p2, A=p2 B=p3"
          % (flag, d["mender_boot_part"]))
    return head, blob


def ungz(src, dst):
    import gzip
    with gzip.open(src, "rb") as fi, open(dst, "wb") as fo:
        shutil.copyfileobj(fi, fo, 4 << 20)


def debugfs_cat(img, path):
    return subprocess.run(["debugfs", "-R", "cat " + path, img], capture_output=True).stdout


def debugfs_ls(img, path):
    """[(name, mode)] of a directory in the image (debugfs `ls -p`: /inode/mode/uid/gid/name/size/)."""
    r = subprocess.run(["debugfs", "-R", "ls -p " + path, img], capture_output=True, text=True)
    out = []
    for line in r.stdout.splitlines():
        f = line.split("/")
        if len(f) >= 6 and f[5] not in (".", "..", ""):
            out.append((f[5], int(f[2], 8) if f[2] else 0))
    return out


def debugfs_exists(img, path):
    r = subprocess.run(["debugfs", "-R", "stat " + path, img], capture_output=True, text=True)
    return "Inode:" in r.stdout


def debugfs_w(img, cmds):
    with tempfile.NamedTemporaryFile("w", suffix=".cmd", delete=False) as f:
        f.write("\n".join(cmds) + "\n"); path = f.name
    try:
        r = subprocess.run(["debugfs", "-w", "-f", path, img], capture_output=True, text=True)
    finally:
        os.unlink(path)
    bad = [l for l in r.stderr.splitlines() if l.strip() and not l.startswith("debugfs ")]
    if bad:
        raise SystemExit("debugfs: " + " | ".join(bad))


def _rm_tree(img, path, removed):
    for name, mode in debugfs_ls(img, path):
        p = path.rstrip("/") + "/" + name
        if (mode & 0o170000) == 0o040000:
            _rm_tree(img, p, removed)
            debugfs_w(img, ["rmdir " + p])
        else:
            debugfs_w(img, ["rm " + p])
        removed.append(p)


# what a system partition read from a running Jooki carries and a release must not:
# the run-time files (/tmp is on the root filesystem on this device), the boot-time copy of the
# Jooki's identity, stray files at /, keys that would let one person into every Jooki
LEFTOVER_FILES = ("/start", "/Not", "/home/root/.ssh/authorized_keys", "/root/.ssh/authorized_keys",
                  "/jooki/app/www/public/openjooki-status.txt", "/jooki/app/www/public/oj-auth.json")
LEFTOVER_DIRS = ("/tmp",)


def scrub_rootfs(img, forget=()):
    """Remove the leftovers of the Jooki the image was dumped from, zero the free blocks (deleted
    files live on there), then make sure none of the `forget` strings remains. Returns what was removed."""
    removed = []
    for p in LEFTOVER_FILES:
        if debugfs_exists(img, p):
            debugfs_w(img, ["rm " + p]); removed.append(p)
    for d in LEFTOVER_DIRS:
        if debugfs_exists(img, d):
            _rm_tree(img, d, removed)
    # One e2fsck -E discard pass right after the removals above does not empty every freed block
    # (measured: the deleted files' bytes were still there, and a second pass cleared them; the new-card
    # image only ever passed its --forget scan because it scrubbed an image scrubbed once already).
    # So: at least two passes, and the last one must have had nothing to repair.
    for n in range(1, 5):
        r = subprocess.run(["e2fsck", "-f", "-y", "-E", "discard", img], capture_output=True, text=True)
        if r.returncode not in (0, 1):
            raise SystemExit("e2fsck -E discard:\n" + r.stdout + r.stderr)
        if r.returncode == 0 and n >= 2:
            break
    else:
        raise SystemExit("e2fsck still repairs the image after four passes:\n" + r.stdout[-400:])
    run(["e2fsck", "-fn", img])
    scan_forbidden(img, forget, quiet=True)
    return removed


def check_rootfs(img, version, forget=(), original=False):
    want = (PARTS[2][1] - PARTS[2][0] + 1) * SECTOR
    if os.path.getsize(img) != want:
        raise SystemExit("the release image is %d bytes, a system partition is %d" % (os.path.getsize(img), want))
    if original:                                   # make_original_rootfs.py: no OpenJooki left
        if debugfs_exists(img, "/etc/openjooki-version"):
            raise SystemExit("--original: this system still has OpenJooki in it")
        v = debugfs_cat(img, "/etc/mender/artifact_info").decode().strip()
    else:
        v = debugfs_cat(img, "/etc/openjooki-version").decode().strip()
        if v != version:
            raise SystemExit("the release image says version %r, not %r" % (v, version))
    if debugfs_cat(img, "/etc/hostname") != b"jooki\n" or debugfs_cat(img, "/etc/mac") != b"":
        raise SystemExit("the release image is not neutral (/etc/hostname, /etc/mac)")
    removed = scrub_rootfs(img, forget)
    print("release image: %s %s, neutral, e2fsck clean; removed %s, free blocks zeroed"
          % ("original system" if original else "OpenJooki", v, ", ".join(removed) if removed else "nothing"))


def check_factory(img):
    """img is a working copy: a stale orphan list (as read from a running Jooki) is repaired here."""
    want = (PARTS[1][1] - PARTS[1][0] + 1) * SECTOR
    if os.path.getsize(img) != want:
        raise SystemExit("the factory partition image is %d bytes, not %d" % (os.path.getsize(img), want))
    r = subprocess.run(["e2fsck", "-fy", img], capture_output=True, text=True)
    if r.returncode not in (0, 1):                         # 1 = errors corrected
        raise SystemExit("e2fsck on the factory partition:\n" + r.stdout + r.stderr)
    fixed = "repaired (%s)" % "; ".join(l.strip() for l in r.stdout.splitlines() if "orphan" in l.lower() or "Fix?" in l)[:200] if r.returncode == 1 else "clean as read"
    run(["e2fsck", "-fn", img])
    for p in ("/etc/hostname", "/etc/mac"):
        if debugfs_cat(img, p):
            raise SystemExit("the factory partition holds %s: not neutral" % p)
    removed = scrub_rootfs(img)
    print("factory partition: %s, e2fsck clean, no name or MAC inside, removed %s, free blocks zeroed; %s"
          % (fixed, ", ".join(removed) if removed else "nothing", debugfs_cat(img, "/etc/mender/artifact_info").decode().strip()))


def mk_ext4(path, size_bytes, staging, label=""):
    with open(path, "wb") as f:
        f.truncate(size_bytes)
    cmd = ["mke2fs", "-q", "-F", "-t", "ext4", "-b", "4096", "-I", "256", "-O", EXT4_FEATURES,
           "-E", "lazy_itable_init=0,lazy_journal_init=0,root_owner=0:0", "-d", staging, path]
    if label:
        cmd[1:1] = ["-L", label]
    run(cmd)
    run(["e2fsck", "-fn", path])


def build_data(work, generic_tar, original=False):
    """p5: only the files every Jooki has (bootloader settings path, device model, update hooks)
    and the flag that says the radio chip is already programmed. Nothing personal."""
    st = os.path.join(work, "data"); os.makedirs(st)
    if generic_tar:
        run(["tar", "xzf", generic_tar, "-C", st, "--strip-components=1"])     # data/u-boot, data/mender/...
    ub = os.path.join(st, "u-boot"); os.makedirs(ub, exist_ok=True)
    fw = os.path.join(ub, "fw_env.config")
    if not os.path.exists(fw):
        open(fw, "w").write("/dev/mmcblk0 0x800000 0x8000\n/dev/mmcblk0 0x1000000 0x8000\n")
    md = os.path.join(st, "mender"); os.makedirs(md, exist_ok=True)
    dt = os.path.join(md, "device_type")
    if not os.path.exists(dt):
        open(dt, "w").write("device_type=ml-j2000\n")
    for bad in ("mender-agent.pem", "mender-store", "mender-store-lock"):        # per-device: never
        if os.path.exists(os.path.join(md, bad)):
            raise SystemExit("the generic data tar holds a per-device file: " + bad)
    os.makedirs(os.path.join(st, "mode"), exist_ok=True)
    open(os.path.join(st, "mode", "ESP32_FIRMWARE_LOADED"), "w").close()
    if not original:
        os.makedirs(os.path.join(st, "openjooki"), exist_ok=True)
    for root, dirs, files in os.walk(st):
        for n in dirs + files:
            os.chown(os.path.join(root, n), 0, 0)
    for root, dirs, files in os.walk(st):
        for d in dirs:
            os.chmod(os.path.join(root, d), 0o755)
    os.chmod(dt, 0o444)
    listing = sorted(os.path.relpath(os.path.join(r, f), st) for r, _, fs in os.walk(st) for f in fs)
    out = os.path.join(work, "p5.img")
    mk_ext4(out, (PARTS[5][1] - PARTS[5][0] + 1) * SECTOR, st)
    print("data partition:", ", ".join(listing))
    return out


def build_content(work):
    """p7: the folders the Jooki expects, all empty (the family's own music goes here)."""
    st = os.path.join(work, "content"); os.makedirs(st)
    for d, own, mode in (("jooki", 1000, 0o775), ("jooki/uploads", 1000, 0o755), ("jooki/artwork", 1000, 0o755),
                         ("jooki/assets", 0, 0o755), ("logs", 0, 0o755), ("logs/syslog-ng", 0, 0o755), ("ota2", 0, 0o755)):
        p = os.path.join(st, d); os.makedirs(p); os.chmod(p, mode); os.chown(p, own, own)
    out = os.path.join(work, "p7.img")
    mk_ext4(out, CONTENT_SECTORS * SECTOR, st)
    return out


def build_config(work):
    """p6: FAT16 named "config", like the Jooki's own (8 sectors per cluster, 512 root entries)."""
    out = os.path.join(work, "p6.img")
    with open(out, "wb") as f:
        f.truncate((PARTS[6][1] - PARTS[6][0] + 1) * SECTOR)
    run(["mkfs.fat", "-F", "16", "-n", "config", "-s", "8", "-R", "8", "-r", "512", "-S", "512", "-h", "0", out])
    run(["fsck.vfat", "-n", out])
    return out


def build_swap(work):
    out = os.path.join(work, "p4.img")
    with open(out, "wb") as f:
        f.truncate((PARTS[4][1] - PARTS[4][0] + 1) * SECTOR)
    run(["mkswap", "-q", out])
    return out


def place(out_fd, src, lba, expect_bytes=None):
    """Copy a partition image into the card image at sector lba; holes stay holes (sparse)."""
    size = os.path.getsize(src)
    if expect_bytes is not None and size != expect_bytes:
        raise SystemExit("%s is %d bytes, expected %d" % (src, size, expect_bytes))
    zero = b"\0" * (1 << 20)
    with open(src, "rb") as f:
        pos = lba * SECTOR
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            if b != zero[:len(b)]:
                os.lseek(out_fd, pos, os.SEEK_SET)
                os.write(out_fd, b)
            pos += len(b)
    return size


def region_sha(path, lba, sectors):
    return sha256_file(path, lba * SECTOR, sectors * SECTOR)


def loop_check(img, lba, sectors, kind):
    """Independent check of one partition inside the image, through a loop device."""
    dev = run(["losetup", "-f", "--show", "-o", str(lba * SECTOR), "--sizelimit", str(sectors * SECTOR), img]).strip()
    try:
        if kind == "ext4":
            run(["e2fsck", "-fn", dev])
        elif kind == "vfat":
            run(["fsck.vfat", "-n", dev])
        elif kind == "swap":
            t = subprocess.run(["blkid", "-p", "-o", "value", "-s", "TYPE", dev], capture_output=True, text=True).stdout.strip()   # -p: probe, never the cache of a reused loop device
            if t != "swap":
                raise SystemExit("p4 is not a swap area (%r)" % t)
    finally:
        subprocess.run(["losetup", "-d", dev], capture_output=True)


def scan_forbidden(path, words, quiet=False):
    """Fail if any of the words appears anywhere in the image (also lower-case, also UTF-16LE)."""
    if not words:
        return
    pats = []
    for w in words:
        for v in {w, w.lower(), w.upper()}:
            pats += [v.encode(), v.encode("utf-16le")]
    keep = max(len(p) for p in pats)
    tail = b""
    with open(path, "rb") as f:
        while True:
            b = f.read(8 << 20)
            if not b:
                break
            buf = tail + b
            for p in pats:
                if p in buf:
                    raise SystemExit("FORBIDDEN: %r is in the image (near byte %d)" % (p, f.tell() - len(buf) + buf.find(p)))
            tail = buf[-keep:]
    if not quiet:
        print("scan: none of %s in the image" % ", ".join(words))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--boot", required=True); ap.add_argument("--factory", required=True)
    ap.add_argument("--rootfs", required=True); ap.add_argument("--version", required=True)
    ap.add_argument("--out", required=True, help="the raw image to write (.img); .gz and sdcard.json go next to it")
    ap.add_argument("--data-tar", help="tar.gz of /data/u-boot, /data/mender/{device_type,mender.conf,scripts} from a Jooki")
    ap.add_argument("--forget", action="append", default=[], help="a string that must not appear in the image (repeatable)")
    ap.add_argument("--keep-work", action="store_true")
    ap.add_argument("--original", action="store_true",
                    help="the original Jooki card: --rootfs comes from make_original_rootfs.py; writes original.json")
    a = ap.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("run as root (mke2fs -d keeps owners, losetup checks the result)")
    for t in ("mke2fs", "e2fsck", "debugfs", "mkfs.fat", "fsck.vfat", "mkswap", "losetup", "blkid", "sgdisk", "gzip"):
        if not shutil.which(t):
            raise SystemExit("missing tool: " + t)
    out = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    work = tempfile.mkdtemp(prefix="ojcard-", dir=os.path.dirname(out))
    t0 = time.time()
    try:
        head, env = check_boot(a.boot)
        rootfs = os.path.join(work, "rootfs.img")             # a working copy: scrubbed below
        if a.rootfs.endswith(".gz"):
            ungz(a.rootfs, rootfs)
        else:
            shutil.copyfile(a.rootfs, rootfs)
        check_rootfs(rootfs, a.version, a.forget, a.original)
        factory = os.path.join(work, "p1.img")                # a working copy: e2fsck may repair it
        if a.factory.endswith(".gz"):
            ungz(a.factory, factory)
        else:
            shutil.copyfile(a.factory, factory)
        check_factory(factory)
        p4 = build_swap(work); p5 = build_data(work, a.data_tar, a.original); p6 = build_config(work); p7 = build_content(work)

        # --- assemble (sparse) ---
        if os.path.exists(out):
            os.unlink(out)
        fd = os.open(out, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            os.ftruncate(fd, TOTAL * SECTOR)
            with open(a.boot, "rb") as f:                       # bootloader + settings, sectors 34.. as read
                f.seek(34 * SECTOR); blob = f.read()
            os.lseek(fd, 34 * SECTOR, os.SEEK_SET); os.write(fd, blob)
            for off in ENV_OFFSETS:                             # both settings copies, identical, at rest
                os.lseek(fd, off, os.SEEK_SET); os.write(fd, env)
            place(fd, factory, PARTS[1][0], (PARTS[1][1] - PARTS[1][0] + 1) * SECTOR)
            place(fd, rootfs, PARTS[2][0], (PARTS[2][1] - PARTS[2][0] + 1) * SECTOR)
            place(fd, rootfs, PARTS[3][0], (PARTS[3][1] - PARTS[3][0] + 1) * SECTOR)
            place(fd, p4, PARTS[4][0]); place(fd, p5, PARTS[5][0]); place(fd, p6, PARTS[6][0])
            place(fd, p7, CONTENT_START, CONTENT_SECTORS * SECTOR)
            # the Jooki's own table, with the content partition ending in this image; the SD tool's
            # grow code then writes both GPT headers, the entries and the protective MBR for TOTAL
            h = bytearray(head)
            struct.pack_into("<Q", h, 1024 + 6 * 128 + 40, CONTENT_START + CONTENT_SECTORS - 1)
            struct.pack_into("<Q", h, 512 + 48, TOTAL - 34)
            struct.pack_into("<I", h, 512 + 88, zlib.crc32(bytes(h[1024:1024 + 128 * 128])))
            h[512:1024] = jooki_sd._header_crc(h[512:1024])
            jooki_sd.write_at(fd, 0, bytes(h))
            n = jooki_sd.grow_content(fd, TOTAL)
            desc = jooki_sd.verify(fd, TOTAL)
            os.fsync(fd)
        finally:
            os.close(fd)
        print("image: %s (%d sectors, %.2f GB; content partition %d sectors) - %s" % (out, TOTAL, TOTAL * SECTOR / 1e9, n, desc))

        # --- independent checks ---
        v = run(["sgdisk", "-v", out])
        if "No problems found" not in v:
            raise SystemExit("sgdisk -v:\n" + v)
        print(run(["sgdisk", "-p", out]).strip().split("\n", 6)[-1])
        for i, kind in ((1, "ext4"), (2, "ext4"), (3, "ext4"), (4, "swap"), (5, "ext4"), (6, "vfat")):
            s, e = PARTS[i]; loop_check(out, s, e - s + 1, kind)
        loop_check(out, CONTENT_START, CONTENT_SECTORS, "ext4")
        print("partitions: e2fsck / fsck.vfat / blkid all clean")
        if region_sha(out, PARTS[2][0], PARTS[2][1] - PARTS[2][0] + 1) != sha256_file(rootfs) \
           or region_sha(out, PARTS[3][0], PARTS[3][1] - PARTS[3][0] + 1) != sha256_file(rootfs):
            raise SystemExit("p2/p3 differ from the (scrubbed) release image")
        if region_sha(out, PARTS[1][0], PARTS[1][1] - PARTS[1][0] + 1) != sha256_file(factory):
            raise SystemExit("p1 differs from the factory image")
        with open(out, "rb") as f:                              # bootloader as read; settings as put at rest
            f.seek(34 * SECTOR); got = f.read(ENV_OFFSETS[0] - 34 * SECTOR)
            with open(a.boot, "rb") as g:
                g.seek(34 * SECTOR); want = g.read(ENV_OFFSETS[0] - 34 * SECTOR)
            if got != want:
                raise SystemExit("bootloader area differs from boot.bin")
            for off in ENV_OFFSETS:
                f.seek(off)
                flag, pairs = env_vars(f.read(ENV_SIZE))
                if flag != 1 or any(dict(pairs).get(k) != v for k, v in ENV_AT_REST.items()):
                    raise SystemExit("bootloader settings on the image are not at rest")
        print("p1, p2, p3 and the bootloader read back identical to their sources; settings at rest in both copies")
        scan_forbidden(out, a.forget)

        # --- the two release files ---
        gz = out + ".gz"
        with open(gz, "wb") as fo:
            subprocess.run(["gzip", "-6", "-c", out], stdout=fo, check=True)
        man = {"version": a.version, "file": os.path.basename(gz), "sha256": sha256_file(gz), "bytes": os.path.getsize(gz),
               "image_bytes": TOTAL * SECTOR, "image_sha256": sha256_file(out), "layout": "jooki-v2-gpt7",
               "min_card_bytes": TOTAL * SECTOR + 1, "date": time.strftime("%Y-%m-%d")}
        mname = "original.json" if a.original else "sdcard.json"
        json.dump(man, open(os.path.join(os.path.dirname(out), mname), "w"), indent=2)
        print("release files: %s (%.0f MB, sha256 %s) + %s   [%d s]"
              % (os.path.basename(gz), man["bytes"] / 1e6, man["sha256"][:16], mname, time.time() - t0))
    finally:
        if not a.keep_work:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
