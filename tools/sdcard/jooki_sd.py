#!/usr/bin/env python3
"""OpenJooki - move a Jooki's content to a bigger SD card (macOS and Linux; Windows has
docs/Jooki-SD-card.cmd). Python 3 standard library only. Needs root to read and write cards.

  sudo python3 jooki_sd.py list                       # the card readers' cards
  sudo python3 jooki_sd.py read  <card> <image>       # the Jooki's card -> image (card only READ)
  sudo python3 jooki_sd.py write <image> <card>       # image -> bigger card, read back, grown
  sudo python3 jooki_sd.py grow  <card>               # only grow a card already copied
  sudo python3 jooki_sd.py new   <card> [--image f]   # a NEW card from scratch (dead Jooki): the
                                                      # complete card image is downloaded, then written
  sudo python3 jooki_sd.py web                        # the same steps in a local web page
<card> is a name from `list` (disk4, sdb, mmcblk0...) or, for tests, an image file.

1. The Jooki's card is only read, never written (the system may add its own small folder to
   the FAT "config" partition when it mounts it; the tool does not). A copy is kept.
2. The copy is written to the new card, read back and compared (SHA-256), then the last GPT
   partition ("content", the music) is grown to the end of the card: protective MBR, both
   headers, entries, CRCs (backup first, so a cut leaves the old, valid layout).
3. Back in the Jooki, its start-up script (S10_init_fs.sh, resize2fs) grows the filesystem.
Only removable cards are offered (never a system or external hard disk); the source must have
the Jooki's layout, the target must be bigger and is confirmed.

A new card from scratch (`new`): the same write, but the source is OpenJooki's complete card
image (tools/sdcard/make_card_image.py: 7 partitions, no family data, about 2.4 GB) fetched from
the "sdcard" GitHub release, checked (SHA-256) and unpacked in the Documents folder first.
"""
import argparse, gzip, hashlib, http.server, json, os, platform, plistlib, secrets, shutil
import struct, subprocess, sys, threading, time, urllib.parse, urllib.request, webbrowser, zlib

SECTOR = 512
CHUNK = 4 << 20
MAX_CARD = 512 * 10**9
BENCH = os.environ.get("JOOKI_SD_BENCH") == "1"     # tests: any block device given by path
# the complete card image lives in its own GitHub release, "sdcard", independent of the firmware
# releases (the Jooki updates itself once it starts); sdcard.json says its name, sizes and SHA-256
RELEASES = "https://github.com/Guillain-RDCDE/OpenJooki/releases"
MANIFESTS = [RELEASES + "/download/sdcard/sdcard.json"]
MIN_NEW_CARD = 3 * 10**9                            # a new card must hold the image and then some


class NotJooki(Exception):
    pass


# ------------------------------------------------------------------ GPT (same rules as the Windows tool)
def check_jooki(head):
    """The first 34 sectors of a Jooki card: GPT, 128 entries of 128 bytes, last partition
    "content", a "config" partition. Returns a short description or raises NotJooki."""
    if head[512:520] != b"EFI PART":
        raise NotJooki("no GPT partition table")
    if zlib.crc32(head[1024:1024 + 128 * 128]) != struct.unpack_from("<I", head, 512 + 88)[0]:
        raise NotJooki("GPT entries damaged")
    last_end, last_name, config, count = -1, None, False, 0
    for i in range(128):
        e = 1024 + i * 128
        if head[e:e + 16] == b"\0" * 16:
            continue
        count += 1
        name = head[e + 56:e + 128].decode("utf-16le", "replace").split("\0")[0]
        end = struct.unpack_from("<q", head, e + 40)[0]
        config = config or name == "config"
        if end > last_end:
            last_end, last_name = end, name
    if last_name != "content" or not config:
        raise NotJooki("not the layout of a Jooki card (%d partitions, last one %r)" % (count, last_name))
    return "%d partitions, music partition ends at sector %d" % (count, last_end)


def read_at(fd, lba, sectors):
    os.lseek(fd, lba * SECTOR, os.SEEK_SET)
    b = bytearray()
    while len(b) < sectors * SECTOR:
        chunk = os.read(fd, sectors * SECTOR - len(b))
        if not chunk:
            raise IOError("short read at sector %d" % lba)
        b += chunk
    return bytes(b)


def write_at(fd, lba, data):
    os.lseek(fd, lba * SECTOR, os.SEEK_SET)
    done = 0
    while done < len(data):
        done += os.write(fd, data[done:])
    os.fsync(fd)


def _header_crc(h):
    h = bytearray(h)
    h[16:20] = b"\0\0\0\0"
    h[16:20] = struct.pack("<I", zlib.crc32(bytes(h[:92])))
    return h


def grow_content(fd, total):
    """Grow the last partition ("content") to the end of the disk. Returns its new size in
    sectors. Raises (writing nothing) if anything is unexpected."""
    head = bytearray(read_at(fd, 0, 34))
    check_jooki(bytes(head))
    hsize, ent_lba, n_ent, ent_sz = struct.unpack_from("<I", head, 524)[0], *struct.unpack_from("<QII", head, 584)
    if (hsize, ent_lba, n_ent, ent_sz) != (92, 2, 128, 128):
        raise NotJooki("unexpected GPT geometry")
    new_last = total - 34
    if new_last < struct.unpack_from("<Q", head, 560)[0]:
        raise NotJooki("the card is smaller than the Jooki's layout")
    idx, last_end = -1, -1
    for i in range(128):
        e = 1024 + i * 128
        end = struct.unpack_from("<q", head, e + 40)[0]
        if head[e:e + 16] != b"\0" * 16 and end > last_end:
            idx, last_end = i, end
    ce = 1024 + idx * 128
    start = struct.unpack_from("<Q", head, ce + 32)[0]
    struct.pack_into("<Q", head, ce + 40, new_last)
    entries = bytes(head[1024:1024 + 128 * 128])
    struct.pack_into("<I", head, 446 + 12, min(total - 1, 0xFFFFFFFF))     # protective MBR length
    primary = bytearray(head[512:1024])
    struct.pack_into("<Q", primary, 32, total - 1)                          # alternate LBA
    struct.pack_into("<Q", primary, 48, new_last)                           # last usable LBA
    struct.pack_into("<I", primary, 88, zlib.crc32(entries))
    primary = _header_crc(primary)
    backup = bytearray(primary)
    struct.pack_into("<QQ", backup, 24, total - 1, 1)                       # my LBA, alternate LBA
    struct.pack_into("<Q", backup, 72, total - 33)                          # entries LBA
    backup = _header_crc(backup)
    write_at(fd, total - 33, entries)
    write_at(fd, total - 1, bytes(backup))
    head[512:1024] = primary
    write_at(fd, 0, bytes(head))
    return new_last - start + 1


def verify(fd, total):
    """Both headers valid, entries CRC valid, the music partition ends at the last usable sector."""
    head = read_at(fd, 0, 34)
    check_jooki(head)
    tail = read_at(fd, total - 33, 33)
    for h in (head[512:1024], tail[32 * 512:]):
        c = bytearray(h[:92]); want = struct.unpack_from("<I", c, 16)[0]; c[16:20] = b"\0\0\0\0"
        if h[:8] != b"EFI PART" or zlib.crc32(bytes(c)) != want:
            raise IOError("GPT header CRC")
    if zlib.crc32(tail[:128 * 128]) != struct.unpack_from("<I", tail, 32 * 512 + 88)[0]:
        raise IOError("backup entries CRC")
    if struct.unpack_from("<Q", head, 560)[0] != total - 34:
        raise IOError("last usable sector")
    return check_jooki(head)


def copy_region(src, dst, src_off, dst_off, length, progress=None):
    """Copy length bytes (dst None: only read), 4 MB at a time; returns the SHA-256."""
    sha = hashlib.sha256()
    os.lseek(src, src_off, os.SEEK_SET)
    if dst is not None:
        os.lseek(dst, dst_off, os.SEEK_SET)
    done = 0
    while done < length:
        want = min(CHUNK, length - done)
        buf = b""
        while len(buf) < want:
            part = os.read(src, want - len(buf))
            if not part:
                raise IOError("short read")
            buf += part
        if dst is not None:
            w = 0
            while w < want:
                w += os.write(dst, buf[w:])
        sha.update(buf)
        done += want
        if progress:
            progress(done, length)
    if dst is not None:
        os.fsync(dst)
    return sha.hexdigest()


def write_card(image, dst, target_bytes, progress=None, status=print):
    """Image -> target: old table erased, data written then read back and compared, then the
    Jooki's table, then the grow and its check. Returns the music partition's new size (sectors)."""
    src = os.open(image, os.O_RDONLY)
    try:
        src_bytes = os.fstat(src).st_size
        head = read_at(src, 0, 34)
        check_jooki(head)
        if target_bytes <= src_bytes:
            raise NotJooki("the new card is not bigger than the Jooki's card")
        data = 34 * SECTOR
        status("erase")
        write_at(dst, 0, b"\0" * data)
        status("write")
        h1 = copy_region(src, dst, data, data, src_bytes - data, progress)
        status("check")
        if hasattr(os, "posix_fadvise"):      # Linux: read the card itself, not what the kernel kept in memory
            os.posix_fadvise(dst, 0, 0, os.POSIX_FADV_DONTNEED)
        h2 = copy_region(dst, None, data, 0, src_bytes - data, progress)
        if h1 != h2:
            raise IOError("the new card did not give back what was written: it may be faulty")
        status("grow")
        write_at(dst, 0, head)
        sectors = grow_content(dst, target_bytes // SECTOR)
        verify(dst, target_bytes // SECTOR)
        return sectors
    finally:
        os.close(src)


# ------------------------------------------------------------------ disks (macOS, Linux)
def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def _mac_info(dev):
    r = subprocess.run(["diskutil", "info", "-plist", dev], capture_output=True, check=False)
    return plistlib.loads(r.stdout) if r.returncode == 0 else {}


def list_cards():
    """[{id, name, size, path, rawpath}] of removable cards only (never a system or fixed disk)."""
    if os.environ.get("JOOKI_SD_DEMO") == "1":           # pictures for the docs: nothing real behind
        return [{"id": "demo", "name": "Generic SD/MMC Card Reader", "size": 7948206080, "path": None, "rawpath": None}]
    if BENCH and os.environ.get("JOOKI_SD_BENCH_CARDS"):  # tests of the page: image files play the cards
        return [{"id": os.path.basename(f), "name": os.path.basename(f), "size": os.path.getsize(f), "path": f, "rawpath": f, "file": True}
                for f in os.environ["JOOKI_SD_BENCH_CARDS"].split(os.pathsep) if os.path.isfile(f)]
    cards = []
    if platform.system() == "Darwin":
        boot = _mac_boot_disk()
        r = subprocess.run(["diskutil", "list", "-plist", "physical"], capture_output=True, check=False)
        for d in plistlib.loads(r.stdout).get("WholeDisks", []) if r.returncode == 0 else []:
            i = _mac_info(d)
            size = int(i.get("TotalSize") or i.get("Size") or 0)
            removable = bool(i.get("RemovableMedia") or i.get("Removable"))     # card readers; not "Fixed" external disks
            if removable and i.get("VirtualOrPhysical") != "Virtual" and d != boot and 1e9 < size <= MAX_CARD:
                cards.append({"id": d, "name": i.get("MediaName") or i.get("IORegistryEntryName") or d,
                              "size": size, "path": "/dev/" + d, "rawpath": "/dev/r" + d})
    elif platform.system() == "Linux":
        root = _linux_root_disk()
        for name in sorted(os.listdir("/sys/block")):
            base = "/sys/block/" + name
            if name.startswith(("loop", "ram", "zram", "dm-", "md", "sr")) or name == root:
                continue
            try:
                removable = open(base + "/removable").read().strip() == "1"
                size = int(open(base + "/size").read()) * 512
            except OSError:
                continue
            if (removable or name.startswith("mmcblk")) and 1e9 < size <= MAX_CARD:
                model = ""
                for f in ("/device/model", "/device/name"):
                    try:
                        model = open(base + f).read().strip() or model
                    except OSError:
                        pass
                cards.append({"id": name, "name": model or name, "size": size, "path": "/dev/" + name, "rawpath": "/dev/" + name})
    return cards


def _mac_boot_disk():
    i = _mac_info("/")
    return i.get("ParentWholeDisk", "")


def _linux_root_disk():
    r = _run(["findmnt", "-n", "-o", "SOURCE", "/"])
    src = os.path.basename(r.stdout.strip())
    for name in os.listdir("/sys/block"):
        if src.startswith(name):
            return name
    return ""


def find_card(ident):
    """A card from the list by its name, or (tests only) an image file / any device with JOOKI_SD_BENCH=1."""
    if os.path.isfile(ident):
        return {"id": ident, "name": os.path.basename(ident), "size": os.path.getsize(ident), "path": ident, "rawpath": ident, "file": True}
    for c in list_cards():
        if c["id"] == os.path.basename(ident) and c["path"]:
            return c
    if BENCH and ident.startswith("/dev/"):
        if platform.system() == "Darwin":                 # macOS block devices report no size by seeking
            size = int(_mac_info(ident).get("TotalSize") or 0)
        else:
            fd = os.open(ident, os.O_RDONLY)
            try:
                size = os.lseek(fd, 0, os.SEEK_END)
            finally:
                os.close(fd)
        raw = "/dev/r" + ident[5:] if platform.system() == "Darwin" and not ident.startswith("/dev/r") else ident
        return {"id": os.path.basename(ident), "name": ident, "size": size, "path": ident, "rawpath": raw}
    raise NotJooki("no such card: %s (see `list`)" % ident)


def unmount(card):
    if card.get("file"):
        return
    if platform.system() == "Darwin":
        _run(["diskutil", "unmountDisk", "force", card["path"]])
    else:
        for part in sorted(os.listdir("/sys/block/" + card["id"])) if os.path.isdir("/sys/block/" + card["id"]) else []:
            if part.startswith(card["id"]):
                _run(["umount", "/dev/" + part])


def reread_table(card):
    if card.get("file"):
        return
    if platform.system() == "Darwin":
        _run(["diskutil", "unmountDisk", card["path"]])
    else:
        _run(["blockdev", "--rereadpt", card["path"]])


def read_card(card, image, progress=None, status=print):
    """Step 1: the Jooki's card -> image. Opened read-only."""
    if card["size"] < 34 * SECTOR or card["size"] % SECTOR:
        raise IOError("cannot read the size of the card (%d bytes)" % card["size"])
    src = os.open(card["rawpath"], os.O_RDONLY)
    try:
        check_jooki(read_at(src, 0, 34))
        out = os.open(image, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        try:
            status("read")
            copy_region(src, out, 0, 0, card["size"], progress)
        finally:
            os.close(out)
    finally:
        os.close(src)
    if os.path.getsize(image) != card["size"]:           # a copy is the whole card, or it is not a copy
        raise IOError("the copy is incomplete (%d of %d bytes)" % (os.path.getsize(image), card["size"]))


def write_card_to_disk(image, card, progress=None, status=print):
    """Step 2: image -> the new card (unmounted first, table re-read at the end)."""
    unmount(card)
    dst = os.open(card["rawpath"], os.O_RDWR)
    try:
        n = write_card(image, dst, card["size"], progress, status)
    finally:
        os.close(dst)
    reread_table(card)
    return n


# ------------------------------------------------------------------ a new card from scratch
def fetch_manifest(urls=None):
    """sdcard.json of the release: {version, file, sha256, bytes, image_bytes, image_sha256...}."""
    last = None
    if not urls and os.environ.get("JOOKI_SD_MANIFEST"):     # tests: a local copy of the release
        urls = [os.environ["JOOKI_SD_MANIFEST"]]
    for u in urls or MANIFESTS:
        try:
            with urllib.request.urlopen(u, timeout=30) as r:
                m = json.loads(r.read().decode())
            if all(k in m for k in ("version", "file", "sha256", "bytes", "image_bytes", "image_sha256")):
                m["url"] = u.rsplit("/", 1)[0] + "/" + m["file"]
                return m
        except Exception as e:                                   # try the next address
            last = e
    raise IOError("cannot fetch the card image's description (%s)" % last)


def file_sha256(path, progress=None):
    h = hashlib.sha256(); total = os.path.getsize(path); done = 0
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b); done += len(b)
            if progress:
                progress(done, total)
    return h.hexdigest()


def download(url, dst, expect_bytes, sha, progress=None, status=print):
    """url -> dst, checked (size, SHA-256). An existing good file is kept as is."""
    if os.path.exists(dst) and os.path.getsize(dst) == expect_bytes and file_sha256(dst) == sha:
        return dst
    status("download")
    part = dst + ".part"
    h = hashlib.sha256(); done = 0
    with urllib.request.urlopen(url, timeout=60) as r, open(part, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b); h.update(b); done += len(b)
            if progress:
                progress(done, expect_bytes)
    if done != expect_bytes or h.hexdigest() != sha:
        os.unlink(part)
        raise IOError("the download is not the published file (size or SHA-256): try again")
    os.replace(part, dst)
    return dst


def unpack(gz, img, expect_bytes, sha, progress=None, status=print):
    """gz -> img (the raw card image), checked (size, SHA-256). An existing good image is kept."""
    if os.path.exists(img) and os.path.getsize(img) == expect_bytes and file_sha256(img, progress) == sha:
        return img
    status("unpack")
    part = img + ".part"
    h = hashlib.sha256(); done = 0
    with gzip.open(gz, "rb") as fi, open(part, "wb") as fo:
        while True:
            b = fi.read(CHUNK)
            if not b:
                break
            fo.write(b); h.update(b); done += len(b)
            if progress:
                progress(done, expect_bytes)
    if done != expect_bytes or h.hexdigest() != sha:
        os.unlink(part)
        raise IOError("the unpacked image is not the published one (size or SHA-256)")
    os.replace(part, img)
    return img


def new_card_image(folder, progress=None, status=print, manifest=None):
    """The complete card image, ready to write: fetched into folder, checked, unpacked, checked."""
    m = manifest or fetch_manifest()
    gz = os.path.join(folder, "Jooki-new-card-%s.img.gz" % m["version"])
    img = os.path.join(folder, "Jooki-new-card-%s.img" % m["version"])
    need = 200 << 20                                          # room for what is not there yet
    if not (os.path.exists(gz) and os.path.getsize(gz) == m["bytes"]):
        need += m["bytes"]
    if not (os.path.exists(img) and os.path.getsize(img) == m["image_bytes"]):
        need += m["image_bytes"]
    free = shutil.disk_usage(folder).free
    if free < need:
        raise IOError("not enough free space in %s: %.1f GB needed" % (folder, need / 1e9))
    download(m["url"], gz, m["bytes"], m["sha256"], progress, status)
    unpack(gz, img, m["image_bytes"], m["image_sha256"], progress, status)
    return img, m


def image_for_new_card(path, progress=None, status=print):
    """--image on the command line: a .img (used as is) or a .img.gz (unpacked next to it, unchecked)."""
    if not path.endswith(".gz"):
        return path
    img = path[:-3]
    if not os.path.exists(img):
        status("unpack")
        with gzip.open(path, "rb") as fi, open(img + ".part", "wb") as fo:
            shutil.copyfileobj(fi, fo, CHUNK)
        os.replace(img + ".part", img)
    return img


# ------------------------------------------------------------------ command line
WORDS = {"read": "Reading the Jooki's card", "erase": "Erasing the old partition table of the new card",
         "write": "Writing (step 1 of 2)", "check": "Checking every byte (step 2 of 2)", "grow": "Growing the music partition",
         "download": "Downloading the card image", "unpack": "Unpacking the card image"}


def _cli_progress(done, total):
    sys.stderr.write("\r  %5.1f %%  %.1f / %.1f GB" % (100.0 * done / total, done / 1e9, total / 1e9))
    if done >= total:
        sys.stderr.write("\n")


def _cli_status(key):
    print(WORDS.get(key, key) + "...", flush=True)


def _need_root(card):
    if not card.get("file") and os.geteuid() != 0:
        raise NotJooki("reading and writing cards needs root: run it with sudo")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Move a Jooki to a bigger SD card (macOS, Linux).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    p = sub.add_parser("read"); p.add_argument("card"); p.add_argument("image")
    p = sub.add_parser("write"); p.add_argument("image"); p.add_argument("card"); p.add_argument("--yes", action="store_true")
    p = sub.add_parser("grow"); p.add_argument("card")
    p = sub.add_parser("new"); p.add_argument("card"); p.add_argument("--image", help="a card image already downloaded (.img or .img.gz)")
    p.add_argument("--yes", action="store_true"); p.add_argument("--folder", help="where the image is downloaded (default: ~/Documents)")
    p = sub.add_parser("web"); p.add_argument("--port", type=int, default=0); p.add_argument("--token")
    p.add_argument("--no-browser", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "new":
            card = find_card(a.card); _need_root(card)
            if card["size"] < MIN_NEW_CARD:
                raise NotJooki("the card is too small (%.1f GB): the new card needs 4 GB or more" % (card["size"] / 1e9))
            if not a.yes and input("Erase EVERYTHING on %s (%s, %.1f GB)? Type yes: " % (card["id"], card["name"], card["size"] / 1e9)).strip() != "yes":
                return 1
            if a.image:
                image = image_for_new_card(a.image, _cli_progress, _cli_status)
            else:
                folder = a.folder or os.path.join(os.path.expanduser("~" + (os.environ.get("SUDO_USER") or "")), "Documents")
                folder = folder if os.path.isdir(folder) else os.getcwd()
                image, m = new_card_image(folder, _cli_progress, _cli_status)
                print("card image: OpenJooki %s (%s)" % (m["version"], image))
            n = write_card_to_disk(image, card, _cli_progress, _cli_status)
            print("OK: a new Jooki card, music partition = %d sectors (%.1f GB). Put it in the Jooki and switch it on." % (n, n * SECTOR / 1e9))
        elif a.cmd == "list":
            for c in list_cards():
                print("%-10s %6.1f GB  %s" % (c["id"], c["size"] / 1e9, c["name"]))
        elif a.cmd == "read":
            card = find_card(a.card); _need_root(card)
            read_card(card, a.image, _cli_progress, _cli_status)
            print("OK: %s (%.1f GB). Keep the Jooki's card safe: it is your way back." % (a.image, card["size"] / 1e9))
        elif a.cmd == "write":
            card = find_card(a.card); _need_root(card)
            if not a.yes and input("Erase EVERYTHING on %s (%s, %.1f GB)? Type yes: " % (card["id"], card["name"], card["size"] / 1e9)).strip() != "yes":
                return 1
            n = write_card_to_disk(a.image, card, _cli_progress, _cli_status)
            print("OK: music partition = %d sectors (%.1f GB). Put the card in the Jooki." % (n, n * SECTOR / 1e9))
        elif a.cmd == "grow":
            card = find_card(a.card); _need_root(card)
            unmount(card)
            fd = os.open(card["rawpath"], os.O_RDWR)
            try:
                n = grow_content(fd, card["size"] // SECTOR); verify(fd, card["size"] // SECTOR)
            finally:
                os.close(fd)
            reread_table(card)
            print("OK: music partition = %d sectors (%.1f GB)" % (n, n * SECTOR / 1e9))
        elif a.cmd == "web":
            return web(a.port, a.token, not a.no_browser)
    except (NotJooki, IOError, OSError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    return 0


# ------------------------------------------------------------------ the local web page (the Mac app's window)
PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jooki: a bigger SD card</title><style>
:root{--bg:#fffbf6;--fg:#222;--muted:#888;--accent:#f26b21;--card:#fff;--line:#e8e2da}
@media (prefers-color-scheme:dark){:root{--bg:#161514;--fg:#eee;--muted:#9a9a9a;--card:#201e1c;--line:#333}}
*{box-sizing:border-box}body{margin:0;font:17px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg);padding:0 20px 40px}
main{max-width:560px;margin:0 auto}h1{color:var(--accent);font-size:1.5em;margin:1em 0 .2em}p{margin:.4em 0 1em}
select,button{font:inherit;width:100%;padding:13px;border-radius:12px;border:1px solid var(--line);background:var(--card);color:var(--fg)}
button{background:var(--accent);color:#fff;border:0;font-weight:700;margin-top:12px;cursor:pointer}button:disabled{opacity:.35;cursor:default}
.ghost{background:transparent;color:var(--accent);border:1.5px solid var(--accent);font-weight:600}
.bar{height:10px;border-radius:5px;background:var(--line);overflow:hidden;margin:18px 0 6px}.bar i{display:block;height:100%;width:0;background:var(--accent)}
.muted{color:var(--muted);font-size:.9em}.err{color:#c43a2f;font-weight:600}</style></head><body><main>
<h1 id="t"></h1><p id="x"></p><select id="s"></select><button class="ghost" id="r"></button><button id="g"></button><button class="ghost" id="h"></button>
<div class="bar"><i id="b"></i></div><div class="muted" id="i"></div></main><script>
var TOKEN=%TOKEN%, fr=(navigator.language||'').slice(0,2)=='fr';
var T={t0:['Your Jooki','Ton Jooki'],x0:['What do you want to do?','Que veux-tu faire ?'],
g0:['A bigger card: more room for music','Une carte plus grande : plus de place pour la musique'],h0:['A new card: my Jooki does not start any more','Une carte neuve : mon Jooki ne démarre plus'],
t1:['1. The Jooki\'s card','1. La carte du Jooki'],x1:['Take the SD card out of the Jooki and put it in this computer (with a card reader if needed), then choose it below. It is only READ: nothing is ever written on it. A copy is kept in your Documents.','Sors la carte SD du Jooki et mets-la dans cet ordinateur (avec un lecteur de cartes si besoin), puis choisis-la ci-dessous. Elle est seulement LUE : rien n\'y est jamais écrit. Une copie est gardée dans tes Documents.'],
g1:['Read the Jooki\'s card','Lire la carte du Jooki'],t2:['2. The new, bigger card','2. La nouvelle carte, plus grande'],x2:['Take out the Jooki\'s card (keep it safe: it is your way back) and put the NEW card in, then click Refresh and choose it. Everything on the new card will be erased.','Retire la carte du Jooki (garde-la précieusement : c\'est ton retour en arrière) et mets la NOUVELLE carte, puis clique sur Actualiser et choisis-la. Tout ce qui est sur la nouvelle carte sera effacé.'],
g2:['Write and enlarge the new card','Écrire et agrandir la nouvelle carte'],t3:['3. Done!','3. C\'est prêt !'],x3:['Put the new card in the Jooki and switch it on. At the first start it uses all the space by itself. If anything goes wrong, just put the old card back.','Mets la nouvelle carte dans le Jooki et allume-le. Au premier démarrage, il utilise tout l\'espace tout seul. En cas de souci, remets simplement l\'ancienne carte.'],
tn1:['A new card for the Jooki','Une carte neuve pour le Jooki'],xn1:['Put a NEW micro SD card (4 GB or more) in this computer, then choose it below: everything on it will be erased. The complete card (about 200 MB to download) is fetched, checked, written and read back: allow about ten minutes.','Mets une NOUVELLE carte micro SD (4 Go ou plus) dans cet ordinateur, puis choisis-la ci-dessous : tout ce qui est dessus sera effacé. La carte complète (environ 200 Mo à télécharger) est récupérée, vérifiée, écrite puis relue : compte une dizaine de minutes.'],
gn1:['Download and write the new card','Télécharger et écrire la carte neuve'],x3n:['Put the card in the Jooki and switch it on. The first start takes a little longer (it prepares the card). Then open the Jooki\'s page as after a first install: its library is empty, ready for your music. It should find your Wi-Fi by itself; if not, set it up as for a new Jooki.','Mets la carte dans le Jooki et allume-le. Le premier démarrage prend un peu plus de temps (il prépare la carte). Ouvre ensuite la page du Jooki comme après une première installation : sa bibliothèque est vide, prête pour ta musique. Il devrait retrouver ton Wi-Fi tout seul ; sinon, règle-le comme pour un Jooki neuf.'],
g3:['Close','Fermer'],r:['Refresh','Actualiser'],none:['No card found: put the card in, then click Refresh.','Aucune carte détectée : mets la carte, puis clique sur Actualiser.'],
confirm:['Erase EVERYTHING on this card?','Effacer TOUT le contenu de cette carte ?'],GB:['GB','Go'],bye:['You can close this page.','Tu peux fermer cette page.'],
read:['Reading the Jooki\'s card...','Lecture de la carte du Jooki...'],erase:['Erasing the old partition table of the new card...','Effacement de l\'ancienne table de la nouvelle carte...'],write:['Writing (step 1 of 2)...','Écriture (étape 1 sur 2)...'],check:['Checking every byte (step 2 of 2)...','Vérification de chaque octet (étape 2 sur 2)...'],grow:['Growing the music partition...','Agrandissement de la partition musique...'],
download:['Downloading the card image...','Téléchargement de l\'image de la carte...'],unpack:['Unpacking the card image...','Décompression de l\'image de la carte...'],
failed:['It did not work: ','Ça n\'a pas marché : ']};
function t(k){return T[k][fr?1:0]}function $(i){return document.getElementById(i)}
function gb(n){return (n/1e9).toLocaleString(fr?'fr-FR':'en-US',{minimumFractionDigits:1,maximumFractionDigits:1})+' '+t('GB')}
function api(p,body){return fetch(p+'?token='+TOKEN,{method:body?'POST':'GET',body:body?JSON.stringify(body):null}).then(function(r){return r.json()})}
var step=0,mode='',busy=false;
function show(){ var x=(step==3&&mode=='new')?'3n':step; $('t').textContent=t('t'+step); $('x').textContent=t('x'+x); $('g').textContent=t('g'+step); $('h').textContent=t('h0'); $('r').textContent=t('r');
  $('s').style.display=$('r').style.display=(step==3||step==0)?'none':''; $('h').style.display=step==0?'':'none'; $('g').disabled=false; }
function cards(){ if(step==0||step==3)return; api('/cards').then(function(c){ var s=$('s'); s.innerHTML='';
  c.forEach(function(d){var o=document.createElement('option');o.value=d.id;o.dataset.size=d.size;o.textContent=d.name+'  ·  '+gb(d.size);s.appendChild(o)});
  $('g').disabled=!c.length; $('i').textContent=c.length?'':t('none'); }); }
function poll(){ api('/status').then(function(st){ if(st.key){$('t').textContent=t(st.key)} if(st.total){$('b').style.width=(100*st.done/st.total)+'%';$('i').textContent=gb(st.done)+' / '+gb(st.total)}
  if(st.running){setTimeout(poll,500);return} busy=false;
  if(st.error){$('i').innerHTML='<span class="err"></span>';$('i').firstChild.textContent=t('failed')+st.error;show();cards();$('g').disabled=false;return}
  step=st.step; mode=st.mode||mode; $('b').style.width='0'; show(); cards(); $('g').disabled=false; }); }
$('r').onclick=cards;
$('h').onclick=function(){ if(busy)return; mode='new'; step='n1'; api('/mode',{mode:mode}).then(function(){show();cards()}); };
$('g').onclick=function(){ if(busy)return; if(step==0){mode='bigger'; step=1; api('/mode',{mode:mode}).then(function(){show();cards()}); return}
  if(step==3){api('/quit',{}).then(function(){document.body.innerHTML='<main><p>'+t('bye')+'</p></main>'});return}
  var o=$('s').selectedOptions[0]; if(!o)return;
  if((step==2||step=='n1')&&!confirm(t('confirm')+'\n\n'+o.textContent))return;
  busy=true; $('g').disabled=true; api(step==1?'/read':step==2?'/write':'/new',{card:o.value}).then(function(){poll()}); };
show(); cards();
</script></body></html>"""


class Job:
    def __init__(self):
        self.lock = threading.Lock()
        self.state = {"step": 0, "mode": "", "running": False, "key": None, "done": 0, "total": 0, "error": None}
        self.image = None
        self.src_size = 0
        self.last = time.time()

    def run(self, fn):
        def go():
            try:
                fn()
            except Exception as e:                                  # shown on the page
                with self.lock:
                    self.state["error"] = str(e)
            finally:
                with self.lock:
                    self.state["running"] = False
        with self.lock:
            self.state.update(running=True, error=None, done=0, total=0)
        threading.Thread(target=go, daemon=True).start()

    def progress(self, done, total):
        with self.lock:
            self.state.update(done=done, total=total)

    def status(self, key):
        with self.lock:
            self.state["key"] = key


def web(port, token, browser):
    token = token or secrets.token_urlsafe(16)
    job = Job()
    # the person's Documents, not root's: the Mac app passes JOOKI_SD_USER, sudo sets SUDO_USER
    import pwd
    user = os.environ.get("JOOKI_SD_USER") or os.environ.get("SUDO_USER")
    who = pwd.getpwnam(user) if user else pwd.getpwuid(os.getuid())
    docs = os.path.join(who.pw_dir, "Documents")
    docs = docs if os.path.isdir(docs) else who.pw_dir

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _ok(self, obj, ctype="application/json"):
            body = obj.encode() if isinstance(obj, str) else json.dumps(obj).encode()
            self.send_response(200); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body)

        def _auth(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            host = (self.headers.get("Host") or "").split(":")[0]
            if q.get("token", [""])[0] != token or host not in ("127.0.0.1", "localhost"):
                self.send_error(403); return False
            job.last = time.time()
            return True

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if not self._auth():
                return
            if path == "/":
                self._ok(PAGE.replace("%TOKEN%", json.dumps(token)), "text/html; charset=utf-8")
            elif path == "/cards":
                with job.lock:
                    step = job.state["step"]
                cards = [c for c in list_cards() if (step != 2 or c["size"] > job.src_size) and (step != "n1" or c["size"] >= MIN_NEW_CARD)]
                self._ok([{"id": c["id"], "name": c["name"], "size": c["size"]} for c in cards])
            elif path == "/status":
                with job.lock:
                    self._ok(dict(job.state))
            else:
                self.send_error(404)

        def do_POST(self):
            path = urllib.parse.urlparse(self.path).path
            if not self._auth():
                return
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n) or b"{}")
            with job.lock:
                busy = job.state["running"]
            if path == "/quit":
                self._ok({"ok": True}); threading.Thread(target=lambda: (time.sleep(0.5), os._exit(0)), daemon=True).start(); return
            if busy:
                self._ok({"ok": False, "error": "busy"}); return
            if path == "/mode":                                   # the first screen's choice
                with job.lock:
                    if job.state["step"] in (0, 1, "n1") and body.get("mode") in ("bigger", "new"):
                        job.state.update(mode=body["mode"], step=1 if body["mode"] == "bigger" else "n1")
                self._ok({"ok": True}); return
            card = next((c for c in list_cards() if c["id"] == body.get("card") and c["path"]), None)
            if not card:
                self._ok({"ok": False, "error": "no such card"}); return
            if path == "/read":
                image = os.path.join(docs, "Jooki-card-%s.img" % time.strftime("%Y%m%d-%H%M"))

                def step1():
                    read_card(card, image, job.progress, job.status)
                    os.chown(image, who.pw_uid, who.pw_gid)          # the copy belongs to the person
                    job.image, job.src_size = image, card["size"]
                    with job.lock:
                        job.state["step"] = 2
                job.run(step1)
            elif path == "/write":
                if not job.image or card["size"] <= job.src_size:
                    self._ok({"ok": False, "error": "not bigger"}); return

                def step2():
                    write_card_to_disk(job.image, card, job.progress, job.status)
                    with job.lock:
                        job.state["step"] = 3
                job.run(step2)
            elif path == "/new":
                if card["size"] < MIN_NEW_CARD:
                    self._ok({"ok": False, "error": "too small"}); return

                def step_new():
                    image, m = new_card_image(docs, job.progress, job.status)
                    for f in (image, image + ".gz"):
                        if os.path.exists(f):
                            os.chown(f, who.pw_uid, who.pw_gid)          # the downloads belong to the person
                    write_card_to_disk(image, card, job.progress, job.status)
                    with job.lock:
                        job.state.update(step=3, mode="new")
                job.run(step_new)
            else:
                self.send_error(404); return
            self._ok({"ok": True})

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
    url = "http://127.0.0.1:%d/?token=%s" % (srv.server_address[1], token)
    print(url, flush=True)

    def idle():                                   # the page left alone for 30 min: stop
        while True:
            time.sleep(30)
            with job.lock:
                running = job.state["running"]
            if not running and time.time() - job.last > 1800:
                os._exit(0)
    threading.Thread(target=idle, daemon=True).start()
    if browser:
        if user and os.geteuid() == 0:          # open the page as the person, not as root
            _run(["sudo", "-u", user, "open" if platform.system() == "Darwin" else "xdg-open", url])
        else:
            webbrowser.open(url)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
