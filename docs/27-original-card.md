# 27 — The original Jooki card (back to factory, without OpenJooki)

A complete SD card with the Jooki 2 **exactly as it was sold**: Muuselabs' own
program of December 2022 (`n20221206-5ce8778-70b40631`), without OpenJooki,
without anyone's music or settings. Made by the SD card tool, third choice:
*The original Jooki: back to the program it was sold with*
([sdcard.html](https://guillain-rdcde.github.io/OpenJooki/sdcard.html)).

Good to know before using it: the official app and Jooki's servers are gone,
so the original program can no longer be set up from a phone. The way back to
OpenJooki is the Jooki's own card (keep it), or a fresh OpenJooki install.

## What is on it

The same layout as every Jooki 2 card and as the new card of
[docs/25](25-new-sd-card.md): the Jooki's bootloader and settings at rest, the
factory partition p1 as read, **the original system on both slots p2 and p3**,
swap, a data partition with only the files every Jooki has, an empty `config`,
an empty music partition grown to the card by the tool.

## How the original system is rebuilt

No Muuselabs image was ever kept whole, but every OpenJooki image keeps each
file it replaces, once, as `<file>.openjooki-orig`, and the 2018 web app in
`public-openjooki-orig/`. `tools/sdcard/make_original_rootfs.py` takes an
OpenJooki release image and:

1. gives every `.openjooki-orig` its name back (the same inode: owner, mode and
   dates as they were);
2. removes what OpenJooki added (the version file, the security start script,
   the new page's files);
3. puts the 2018 web app back in the served folder;
4. checks that nothing named *openjooki* is left, zeroes the free blocks and
   runs `e2fsck`.

The first OpenJooki images kept their own page as the "original" `index.html`
and `service-worker.js`: those two are taken from a backup of a Jooki made
before OpenJooki (`--check`). The same backup is then compared **in both
directions**: every file of `/jooki/app`, `/jooki/bin` and `/jooki/lib` must be
identical byte for byte, and nothing may be there that the backup does not
have. The 29 September 2026 build: 163 files identical, nothing extra.

```
sudo python3 tools/sdcard/make_original_rootfs.py openjooki-firmware-2.0.5.img.gz out/original-rootfs.img \
     --check jooki-system.tar.gz --forget <name> --forget <MAC>
sudo python3 tools/sdcard/make_card_image.py --original --boot boot.bin --factory p1.img \
     --rootfs out/original-rootfs.img --version original-2022-12 --out out/jooki-original-2022-12.img \
     --data-tar data-generic.tar.gz --forget <name> --forget <MAC>
```

The card lives in its own GitHub release, `original`
(`jooki-original-2022-12.img.gz` + `original.json`, read by the tools at
`releases/download/original/original.json`). It does not change with OpenJooki
releases: the original program does not change any more.

## Not verified yet

Checked on images and on a card written from the published release (table,
every file system, the system files). **Not yet started in a real Jooki.**
