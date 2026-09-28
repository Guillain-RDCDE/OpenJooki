# A new SD card from scratch (a Jooki that no longer starts)

The most frequent breakdown of a Jooki v2 is its micro SD card: the Jooki no longer
starts, the two side dots stay dark, a reset does nothing, and the card, once taken
out, is unreadable or full of errors. Everything the Jooki is lives on that card. Until
now the only cure was a copy of someone else's card, with their family's music and
their Jooki's name on it.

OpenJooki now publishes a **complete card image**, made from scratch, with nothing
personal on it, and the SD card tool writes it on a blank card. This page is the
plain-words guide first, then what is on the card, for the curious.

## In plain words

You need a computer with a card reader (Windows, Mac or Linux), a **new micro SD card
of 4 GB or more** (8 to 32 GB is the sweet spot), and about ten minutes.

1. Open the Jooki (the four screws under it) and take its card out. Keep it.
2. Download the tool from **[the SD card page](https://guillain-rdcde.github.io/OpenJooki/sdcard.html)**
   and open it. The first screen asks what you want; choose **A new card: my Jooki
   does not start any more**.
3. Put the new card in the computer, choose it in the list, and confirm that
   everything on it may be erased.
4. Wait. The tool downloads the card image (about 200 MB), checks it, writes it, reads
   the card back and compares every byte, then gives the music all the room of the card.
5. Put the card in the Jooki and switch it on. The first start takes a little longer,
   because the Jooki prepares the card. Then open its page as after a first install
   (`http://jooki2-xxxxxx.local/`, or its address on your Wi-Fi box): the library is
   empty, ready for your music. The Jooki should find your Wi-Fi by itself, because
   the Wi-Fi settings live in its radio chip, not on the card; if it does not, set it
   up as for a new Jooki.

If it does not start on the new card either, the trouble is not the card: look at
the battery and the charging port before anything else (a Jooki whose battery is
flat shows nothing at all until it has charged for a while).

## What is on the card

The card has exactly the layout of a factory card: a GPT with seven partitions,
the same sectors, the same names and the same partition identifiers as a real Jooki.

| Partition | Sectors | Content on the new card |
|---|---|---|
| bootloader (no partition) | 34 to 49151 | the Jooki's own bootloader, as read from a Jooki, and its settings put at rest (no update pending, boot counter at zero, system A first) |
| p1 `factory` | 49152 to 573439 | the factory system of 2021, as read from a Jooki (the bootloader's last resort) |
| p2 `primary` | 573440 to 2080767 | OpenJooki, the release image |
| p3 `primary` | 2080768 to 3588095 | OpenJooki again: the bootloader always has a second system to fall back on |
| p4 `swap` | 3588096 to 3719167 | a fresh swap area |
| p5 `primary` (/data) | 3719168 to 3981311 | only the files every Jooki has: where the bootloader settings are, the device model, the update hooks, and the flag that says the radio chip is already programmed |
| p6 `config` | 3981312 to 4505599 | an empty FAT16 named `config`, as the factory makes it |
| p7 `content` | 4505600 to the end | an empty music partition with the Jooki's folders; the tool grows it to the end of the card and the Jooki grows the filesystem at its first start (its own `S10_init_fs.sh` runs `resize2fs` at every boot) |

The published image stops right after a 128 MB music partition, about 2.4 GB in
all, so that it fits any card of 4 GB or more. Nothing from the family that lent
its Jooki is on it: the build refuses to finish if that Jooki's name or MAC address
appears anywhere in the result, and the Jooki writes its own name and address at
every boot from its radio chip anyway.

Two things are not on the card and do not need to be: the Wi-Fi networks (kept in
the radio chip's own memory) and the Spotify login (a file the family recreates
from the page, if they use it).

## How it is built and checked

`tools/sdcard/make_card_image.py` (Linux, root) assembles the image from three
pieces read on a Jooki over SSH (the first 24 MiB of the card, the factory
partition, and the generic files of `/data`) plus the release image, then checks
it with the reference tools: `sgdisk -v` finds no problem, `e2fsck -fn` is clean
on every ext4 partition, `fsck.vfat` on the FAT one, `blkid` sees the swap, p1, p2,
p3 and the bootloader read back identical to their sources, the settings are at
rest in both copies, and the forbidden strings are absent. It writes the `.img.gz`
and `sdcard.json` (name, sizes and SHA-256 of both the archive and the raw image).

## Where it lives, and when it changes

The two files are attached to a GitHub release of their own, **`sdcard`**, on purpose
not the "latest" one (the Jooki's updater reads `latest`). The tools read
`https://github.com/Guillain-RDCDE/OpenJooki/releases/download/sdcard/sdcard.json`
and nothing else, so someone whose Jooki died a year from now lands on the page, runs
the tool and gets a card that starts, whatever firmware releases happened meanwhile.

The card is a starting point, not the newest OpenJooki: once the Jooki starts on it
and finds its Wi-Fi, its own page offers the newest version and installs it, by the
update path every Jooki already uses. So the card image is **not** rebuilt at each
release. It is rebuilt only when the card itself has to change:

- the bootloader, the partition layout, the factory partition or the files of `/data`
  it carries (has not happened since the Jooki 2 exists);
- the system it embeds becomes too old to update itself (only if the update mechanism
  changes shape: `version.json` and the scripts on the Pages site);
- optionally, now and then, so that a first start does not begin too far behind.

To rebuild: `make_card_image.py` with the same three pieces (kept off the repository)
and the newest release image, then `gh release upload sdcard <the .gz> sdcard.json --clobber`,
and a line in the `sdcard` release notes saying which OpenJooki is inside.

The tools then do what they already did for a bigger card: write, read back and
compare, grow the last partition, verify both GPT headers. What has been tested is
in [tools/sdcard/README.md](../tools/sdcard/README.md).
