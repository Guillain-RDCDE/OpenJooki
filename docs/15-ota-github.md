# Update via GitHub (OTA) — design

> As built and in use (2.2.7). How a release is made and published:
> [28-release.md](28-release.md).

Replace Muuselabs' dead cloud with **our own GitHub repo**, which the Jookis
fetch from on their own. Simple and safe, suited to a music player for kids (no
signing infrastructure to manage).

## Two hosts, on purpose
- **GitHub Pages** (`https://guillain-rdcde.github.io/OpenJooki/`) serves the
  **installer page** and the **updater scripts** — `o.sh` (update entry point),
  `b.sh` (first-install bootstrap), `openjooki-ota.sh`, `openjooki-selfupdate.sh`.
  These deploy with a plain `git push` (the `docs/` folder), so fixing a script
  needs no release upload and no `gh` login.
- **GitHub Releases** hold the heavy, rarely-changing bits: the firmware image
  `openjooki-firmware-X.Y.Z.img.gz` and `version.json`
  (`{ "version", "file", "sha256", "device_type", "date", "ota_sha256", "selfupdate_sha256",
  "o_sha256" }`), produced by `scripts/make-release.sh <image> <version>`, which
  `scripts/release.sh` runs ([28-release.md](28-release.md)); and, since the updater hashes, a
  copy of `openjooki-ota.sh` and `openjooki-selfupdate.sh` as they were in the release's commit.

The device downloads the firmware from the Release, and the updater scripts from the Release
(Pages when the Release has no good copy), checked against the sha256 `version.json` gives.
`o_sha256` (the hash of `o.sh` itself) is written for a later check by the core; nothing reads
it yet.

## Flow on the Jooki
1. **Front door**: on an OpenJooki 2.x, the page's *Update* button. The core's `update_check`
   and `update_start` shell actions fetch `version.json` and `o.sh` from the two addresses of its
   configuration (`update_manifest_url`, `update_script_url` in `core/kernel/config.lua`), and
   accept an address only on our GitHub (`github.com/Guillain-RDCDE/OpenJooki/`,
   `guillain-rdcde.github.io/OpenJooki/`) or on `127.0.0.1` for the bench
   (`is_update_url` in `core/adapters/shell.lua`). On a factory Jooki, the phone
   installer page (`docs/index.html`) fires one command at the factory web control (`/ll`,
   gone from OpenJooki since 2.1) — see `docs/16-phone-install.md`.
2. `b.sh`/`o.sh` fetch `version.json` of the latest release, then `openjooki-ota.sh` +
   `openjooki-selfupdate.sh`: each from the release first, from Pages when the release has no
   copy with the sha256 `version.json` gives (`ota_sha256`, `selfupdate_sha256`; `sha256sum |
   cut`, the same `sed` reading as `openjooki-ota.sh`). Both right: they replace the old ones in
   `/data/openjooki/`. One wrong: *updater rejected, nothing changed*, exit 3, the downloaded
   files deleted, the old ones kept, nothing run. A release made before these fields (2.4.1 and
   before) gets the Pages copies as it always did, unchecked, and the log says *updater not
   verified*. Bench: `tools/openjooki/tests/test_updater.py` (busybox, in CI).
3. `openjooki-ota.sh` reads the installed version (`/etc/openjooki-version`),
   fetches `version.json`, and — only if the version differs and the
   **`device_type` matches** (`ml-j2000`) — downloads the image and **verifies
   its sha256** (rejects a mismatch, changes nothing).
4. `openjooki-selfupdate.sh` writes the **spare** partition, checks it
   **bit-for-bit**, confirms it is bootable, **arms the U-Boot rollback**, and
   switches. A commit-on-boot hook disarms the rollback after a healthy boot.

## Resilience: retry every download
Every `curl` in the scripts goes through a small `dl()` helper that **retries up
to 5 times** (re-resolving DNS each attempt). This exists because a single
**transient DNS failure** mid-download (seen in the wild on the release CDN,
`release-assets.githubusercontent.com`) used to abort the whole install; the
retry recovers from it automatically. The install still aborts safely — device
unchanged — if every attempt fails.

## Security, calibrated for the use case
- **HTTPS** (GitHub) + the manifest's **sha256** = the received image is intact
  and really comes from the release. The updater scripts too, once the latest release gives
  their hashes: from then on a change on Pages alone (the `docs/` folder deploys on every push)
  cannot run on a Jooki until a release carries it.
- **`device_type` gate** = a v1 (or any other model) is refused before any write.
- **A/B + armed rollback** = even a valid-but-shaky image cannot brick.
- No signing keys to manage: unnecessary in this context.

## Scope / rights
The repository publishes **our** code (the core, the page, the tools, the OTA
mechanism, the installer page; the 1.x patches left with ADR-0012). Firmware images that bundle third-party binaries belong to their authors;
publish only with consent, otherwise keep them as a private release / built from
your own device.

## To include in the image
Every firmware must contain `/etc/openjooki-version`, so the Jooki knows where it
stands. The updater scripts live in `/data/openjooki/` (the data partition,
preserved from one version to the next).
