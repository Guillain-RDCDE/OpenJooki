# The Jooki's SD card: a bigger one, a new one, or the original one (Windows, Mac, Linux)

> **Parents**: everything you need is on [the tool's page](https://guillain-rdcde.github.io/OpenJooki/sdcard.html).
> This file is for those who want to know how the tool works.

The Jooki 2 keeps everything on a micro SD card inside it: 8 GB, of which about
5 GB is for music. The tool does three things, chosen on its first screen (the third, the
original Jooki, is described further down):

- **a bigger card**: it copies the Jooki's card to a bigger one, for more music;
- **a new card from scratch**: for a Jooki that no longer starts because its card is
  dead. It downloads OpenJooki's complete card image (no family data on it), writes it
  on a blank card, and the Jooki starts again. Plain-words guide and what is on that
  card: [docs/25-new-sd-card.md](../../docs/25-new-sd-card.md).

- **Windows**: [`Jooki-SD-card.cmd`](../../docs/Jooki-SD-card.cmd), one file, nothing to install;
- **Mac**: the app **Jooki SD Card** ([zip](../../docs/Jooki-SD-Card-mac.zip), built by `make_mac_zip.py`
  from [`Jooki SD Card.app`](Jooki%20SD%20Card.app) and `jooki_sd.py`): it asks for the password,
  then the steps open in the browser;
- **Linux** (and Mac in a terminal): [`jooki_sd.py`](jooki_sd.py), Python 3 standard library:
  `sudo python3 jooki_sd.py web`, or `list`, `read <card> <image>`, `write <image> <card>`, `grow <card>`,
  `new <card>` (a new card from scratch; `--image` to use a card image already downloaded).

## What you need

- A Windows 10/11 computer, a Mac or a Linux computer, with a card reader (built in, or a small USB one).
- A new micro SD card: **bigger than 8 GB** for a bigger card, **4 GB or more** for a new
  card or the original Jooki. Up to 32 GB is the same kind of card as the Jooki's own; bigger cards (SDXC) have not been tried in a Jooki yet.
- About 8 GB free in your Documents folder.

## How to

1. Download it from **[the tool's page](https://guillain-rdcde.github.io/OpenJooki/sdcard.html)**
   (the file itself: [`docs/Jooki-SD-card.cmd`](../../docs/Jooki-SD-card.cmd)).
2. Open the Jooki and take its card out.
3. Double-click the file and say **Yes** when Windows asks for permission (it needs it
   to read and write cards). Then follow the window:
   - **The Jooki's card**: it is only **read**, never written. A copy is kept in your
     Documents: it is also a backup.
   - **The new card**: it is written, **read back and compared**, then the music space
     is stretched to the whole card.
4. Put the new card in the Jooki and switch it on. At the first start it uses all the
   space by itself.

Keep the old card: if anything goes wrong, put it back and the Jooki is exactly as before.
If Windows offers to format the new card afterwards, say **Cancel**: the Jooki uses
formats Windows cannot read.

## How it works

- Only card readers are offered (an SD/MMC bus, or USB media Windows reports as
  removable), never a system disk or an external hard disk. The source must have the
  Jooki's layout (GPT, last partition `content`, a `config` partition); the target must
  be bigger, and its name and size are confirmed before it is erased.
- On the new card: the old partition table is erased, the data is written after it,
  read back and compared (SHA-256), then the table is written and the last partition
  (`content`) is grown to the end of the card: protective MBR, primary and backup GPT
  headers, entries and CRCs (backup first, so a cut leaves the old, valid layout).
- The Jooki's own start-up script (`S10_init_fs.sh`, `resize2fs`) then grows the
  filesystem to the new partition at the first boot. OpenJooki updates never touch
  that partition.

### A new card from scratch

- The source is not the Jooki's card but OpenJooki's **complete card image**, built by
  [`make_card_image.py`](make_card_image.py) (Linux, root) from three pieces read on a
  Jooki (the first 24 MiB of the card with the bootloader, the factory partition p1,
  the generic files of `/data`) and the release image, on both system slots. Fresh
  swap, an empty `config` FAT16, an empty music partition of 128 MB with the Jooki's
  folders; the image stops there (about 2.4 GB), so any card of 4 GB or more will do.
  The bootloader settings are put at rest (no update pending, boot counter at zero,
  system A first). The build fails if the lending Jooki's name or MAC address is
  anywhere in the result.
- The image and `sdcard.json` (name, sizes, SHA-256 of the archive and of the raw image)
  live in a GitHub release of their own, `sdcard`, at a fixed address independent of the
  firmware releases, and rebuilt with every release so that the card starts on the newest
  OpenJooki (the procedure: [docs/25-new-sd-card.md](../../docs/25-new-sd-card.md)).
  The tools read `releases/download/sdcard/sdcard.json`, download the archive into
  Documents, check it, unpack it, check the image, then do exactly the bigger-card
  write: erase the table, write, read back and compare, grow `content` to the end of
  the card, verify both GPT headers. A card image already downloaded and checked is
  reused as is.
- Only cards of 4 GB or more are meant for a new card (what the page and the error message
  say). The test in the code is 3 × 10⁹ bytes (`MIN_NEW_CARD` in `jooki_sd.py`, `$MinNewCard`
  in `docs/Jooki-SD-card.cmd`): "a new card must hold the image and then some", and the
  image is about 2.4 GB.

### The original Jooki

- The third choice writes the same kind of complete card, but with the Jooki's own program
  of December 2022 on both system slots, without OpenJooki: rebuilt from a release image by
  [`make_original_rootfs.py`](make_original_rootfs.py), then `make_card_image.py --original`.
  Its own GitHub release, `original` (`original.json`), read the same way. Command line:
  `sudo python3 jooki_sd.py new <card> --original`. How it is rebuilt and checked:
  [docs/27-original-card.md](../../docs/27-original-card.md).

## Tested

- On disk images: a card with the Jooki's layout copied to a bigger one, checked with
  `sgdisk -v`, `e2fsck` and a `resize2fs` like the Jooki's, the files kept; the real
  partition table of a Jooki grown to 32 GB; a target that is not bigger, and a card
  that is not a Jooki's, refused with nothing written.
- On real Windows disks (two virtual disks attached by Windows, the window's own two
  steps): the Jooki card's FAT `config` partition mounted by Windows, the new card
  formatted FAT32 and mounted, as bought. The new card was erased, written, read back,
  grown, and passed the same checks; Windows then shows the Jooki's partitions on it.
- The Python tool (Mac, Linux), the same checks: on Linux with a real block device
  (a mounted volume on the new card, unmounted by the tool, the new table read by the
  kernel); on macOS with disks attached by the system (`/dev/rdisk`, the Jooki card's FAT
  partition mounted by macOS), then checked with the Linux reference tools.
- The Mac app on a Mac: unzipped by the Finder and by `unzip`, the launcher stays
  executable, the page runs with the needed rights and refuses any request without its
  secret token or from another host name. The password dialog itself is macOS's own.
- The new card (28 September): the image itself, partition by partition, with the Linux
  reference tools (`sgdisk -v`, `e2fsck -fn` on the five ext4 partitions, `fsck.vfat`,
  `blkid`, the sources read back identical, the bootloader settings parsed back, the
  lending Jooki's name and MAC absent). Then the three ways of writing it, all on card
  files, each card checked the same way plus the Jooki's own first-boot step
  (`resize2fs` on the music partition, then `e2fsck`): the Python tool from a local image
  (8 GB card), from a local copy of the release over HTTP (32 GB card), from the real
  GitHub release (8 GB card); the Windows tool from the archive (5 GB card) and its
  download, its reuse of good files and its refusal of a corrupted archive; the web page
  driven by a browser from the first screen to "Done" (8 GB card); a card of 2 GB
  refused and a corrupted download refused, both with nothing written.
- Not yet: a physical card in a card reader, a Jooki started on a bigger card, and a
  Jooki started on a new card made this way. The bootloader, its settings and the
  factory partition are byte-for-byte those of a working Jooki, and the system
  partitions are the release every Jooki runs; the first real start is the test that
  remains.

Note: the tool never writes to the Jooki's card, but **the computer itself** writes a few
sectors in the FAT `config` partition of any card it mounts (Windows: a `System Volume
Information` folder, which the Jooki's own card already has; macOS: its own small files).
The Jooki ignores them; the music is not touched.

Bench (Windows tool), no window: `JOOKI_SD_TEST="clone|<src.img>|<dst.img>"` or
`JOOKI_SD_TEST="grow|<card.img>"`; `JOOKI_SD_PREVIEW=<file.png>` draws the window.

Bench (Python tool): an image file works as a card (`read src.img card.img`, `write card.img dst.img --yes`);
`JOOKI_SD_BENCH=1` also accepts any block device path; `JOOKI_SD_DEMO=1` shows an example card reader (pictures).
