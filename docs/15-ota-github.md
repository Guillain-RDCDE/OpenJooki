# Update via GitHub (OTA) — design

Replace Muuselabs' dead cloud with **our own GitHub releases**, which the Jookis
fetch on their own. Simple and safe, suited to a music player for kids (no
signing infrastructure to manage).

## Release format
A GitHub release (tag `vX.Y.Z`) contains two files:
- `openjooki-firmware-X.Y.Z.img.gz` — the compressed image.
- `version.json` — `{ "version", "file", "sha256", "date" }`.

Both are generated with `scripts/make-release.sh <image> <version>`.

## Jooki side: `tools/openjooki/device/openjooki-ota.sh`
1. reads the installed version from `/etc/openjooki-version` (present in every image);
2. downloads `version.json` from `…/releases/latest/download/` (HTTPS);
3. if the version differs, downloads the image, **verifies the sha256** (reject if wrong);
4. runs `selfupdate.sh`: write to the **spare** partition, **bit-perfect**
   verification, "bootable" check, **U-Boot rollback arming**, switch.

Triggering: by hand (`sh openjooki-ota.sh`), later an "Update" button on the
Jooki's web page, or a periodic check.

## Security, calibrated for the use case
- **HTTPS** (GitHub) + the manifest's **sha256** = the received image is intact and
  really comes from the release.
- **A/B + armed rollback** = even a valid but shaky image cannot brick.
- No signing keys to manage: unnecessary in this context.

## Scope / rights
The repository publishes **our** code (tools, patches, OTA mechanism). Firmware
images that bundle third-party binaries belong to their authors; publish only
with their consent, otherwise keep them as a private release / built from your
own device. The OTA mechanism points at the repository's releases: it's up to you
to make them public or private.

## To include in the image
Every firmware must contain `/etc/openjooki-version` (the version it represents),
so the Jooki knows where it stands. `selfupdate.sh` and `openjooki-ota.sh` live
in `/data/openjooki/` (data partition, preserved from one version to the next).
