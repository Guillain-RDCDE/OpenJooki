# A bigger SD card for the Jooki (Windows)

The Jooki v2 keeps everything on a micro SD card inside it: 8 GB, of which about
5 GB is for music. To get more room, move it to a bigger card with
**`Jooki-SD-card.cmd`**: one file, nothing to install.

## What you need

- A Windows 10 or 11 computer with a card reader (built in, or a small USB one).
- A new micro SD card, **bigger than 8 GB**. Up to 32 GB is the same kind of card as
  the Jooki's own; bigger cards (SDXC) have not been tried in a Jooki yet.
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

## Tested

- On disk images: a card with the Jooki's layout copied to a bigger one, checked with
  `sgdisk -v`, `e2fsck` and a `resize2fs` like the Jooki's, the files kept; the real
  partition table of a Jooki grown to 32 GB; a target that is not bigger, and a card
  that is not a Jooki's, refused with nothing written.
- On real Windows disks (two virtual disks attached by Windows, the window's own two
  steps): the Jooki card's FAT `config` partition mounted by Windows, the new card
  formatted FAT32 and mounted, as bought. The new card was erased, written, read back,
  grown, and passed the same checks; Windows then shows the Jooki's partitions on it.
- Not yet: a physical card in a card reader, and a Jooki started on a bigger card.

Note: the tool never writes to the Jooki's card, but **Windows itself** adds a small
`System Volume Information` folder to the FAT `config` partition of any card it mounts
(the Jooki's own card already has one). The Jooki ignores it; the music is not touched.

Bench mode, no window: `JOOKI_SD_TEST="clone|<src.img>|<dst.img>"` or
`JOOKI_SD_TEST="grow|<card.img>"`; `JOOKI_SD_PREVIEW=<file.png>` draws the window.
