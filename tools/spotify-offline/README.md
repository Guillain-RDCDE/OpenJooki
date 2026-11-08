# Experimental Spotify offline player trial

This builds [CormAlan/spotify-player-offline-mode](https://github.com/CormAlan/spotify-player-offline-mode)
at revision `cd47e7594b2f564c52a07751c6c4b0f27b26af06` with reviewed local patches.
It uses separate configuration and downloads, without replacing a Jooki service.
The upstream code in the patches retains its [MIT notice](LICENSE.spotify-player).

## Native build and checks

Requirements: Python **3.11+**, Git, Rust/Cargo and native audio development
libraries (ALSA development files on Linux). Tested with Rust **1.99.1** on macOS.
The first build fetches the pinned source and locked Cargo dependencies.

```sh
python3 tools/spotify-offline/trial.py check
python3 tools/spotify-offline/trial.py run -- --version
python3 tools/spotify-offline/smoke.py
```

`check` builds the minimal Rodio/Rustls profile and runs download/storage tests.
`smoke.py` creates encrypted synthetic silence with an invented key, then lists
and decodes it in two fresh processes with macOS networking denied. It requires
`openssl` and `sandbox-exec`; it does not authenticate or open an audio device.

The helper checks the source revision and exact patch diff before every run.
Other tracked, staged or untracked source changes cause an error. Use another
`--work-dir` rather than overwriting a modified checkout. All generated files
are under ignored `build/spotify-offline/trial/` by default.

The native profile applies `player.patch`, combining:

- The registered ncspot callback correction to `/ncspot_login` in both Web API
  branches; the streaming callback remains `/login`.
- Bounded audio I/O: SD spooling, 8 KiB checksum buffers and seekable encrypted
  file regions, plus decoding/seek probes and timed headless playback.
- The Unix `downloads managed` interface: exact ordered playlists, private
  account namespaces, immutable verified generations, quota checks, atomic
  progress/catalog files, resumable sync and acknowledged playback controls.
- The fork's own documentation and seven transaction tests. Synchronization
  refreshes cached authentication without opening a browser. Missing or
  unsupported playlist entries fail the sync rather than silently disappearing.

The MIPS build applies the TLS overlay **after** this patch. Profile checks compose
patches through a temporary Git index, including overlapping Cargo edits and new
files. `python3 tools/spotify-offline/test_profiles.py` verifies the guards without
network or an account. Source changes outside the reviewed profiles are refused.

## Download and verify a playlist

Spotify Premium and a separate interactive sign-in are required. Run from the
repository root, replacing the example URI:

```sh
python3 tools/spotify-offline/trial.py run -- downloads add 'spotify:playlist:PLAYLIST_ID'
python3 tools/spotify-offline/verify.py 'spotify:playlist:PLAYLIST_ID'
python3 tools/spotify-offline/trial.py run -- downloads probe 'spotify:playlist:PLAYLIST_ID'
python3 tools/spotify-offline/trial.py run -- downloads play 'spotify:playlist:PLAYLIST_ID'
python3 tools/spotify-offline/trial.py run -- downloads play 'spotify:playlist:PLAYLIST_ID' --headless --duration 20
```

The downloader opens browser authentication and collects the loopback callback.
No password or callback code needs to be copied into the terminal. More than
one consent page can appear because streaming and Web API authentication differ.

Configuration, account credentials/cache and downloads stay in
`build/spotify-offline/trial/private/`, with owner-only directory permissions.
The stock controller's credentials are not imported. New processes use umask
077. Initial playback volume is 20% and bitrate is 96 kbit/s; existing settings
are preserved. Track listings omit playback keys. Download payloads and token
files must remain outside Git.

`verify.py` requires macOS. It refuses an empty playlist or missing members,
then fully decodes the downloads twice in fresh processes with networking
**denied by `sandbox-exec`**. It records playlist order, public metadata, binary
and patch hashes under `private/`. It fails if the binary changes during the
check. The player itself still permits partial selections; this helper checks
completeness separately.

The interactive offline player starts paused and accepts Enter/Space to play
and `q` to quit. `--headless --duration 20` starts immediately without a terminal,
stops after 20 seconds, and returns JSON status or an audio error. The duration
is 1–300 seconds, default 30. This is a bounded output test, not a control daemon. A successful decode/seek check does not establish
speaker output or a cold device reboot.

## Experimental Jooki cross-build

`mips.py` builds a static MIPS32r2 o32 hard-float/FP32 player with the ALSA
backend. The target is experimental and uses `build-std` plus the host
compiler's matching `rust-src`; it is not an official prebuilt Rust target.
`mips-tls.patch` switches librespot and rspotify to Rustls/WebPKI, preserving
certificate verification and avoiding target OpenSSL. Its `Cargo.lock` changes
are included.

The prepared toolchain used here is the local linux/amd64 Docker image
`openjooki-firmware-port-tools:local`, ID
`sha256:3f1dce4bf3900437b5729cb99c15bdcb07108a3a1f207c061479b32268a89805`.
It supplies GCC **9.4**, musl **1.2.3**, Linux headers, Make and pkg-config, with
`/opt/oj-mips/bin/musl-gcc` and `/usr/bin/mipsel-linux-gnu-{ar,ranlib}`.
This image must already exist locally; no proprietary Spotify SDK is required.

Prepare the following artifacts under the chosen work directory:

1. Build **ALSA 1.2.14** from
   `https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.14.tar.bz2`, SHA-256
   `be9c88a0b3604367dd74167a2b754a35e142f670292ae47a2fdef27a2ee97a32`.
   In the container, mount the work directory at its **same absolute path** and
   run the following from the extracted source, substituting that path:

   ```sh
   CC=/opt/oj-mips/bin/musl-gcc AR=mipsel-linux-gnu-ar RANLIB=mipsel-linux-gnu-ranlib \
   STRIP=mipsel-linux-gnu-strip \
   CFLAGS='-Os -march=mips32r2 -mfp32 -idirafter /usr/mipsel-linux-gnu/include' \
   ./configure --host=mipsel-linux-musl --prefix=/usr --enable-static --disable-shared --disable-python
   make -j4
   make DESTDIR=/ABSOLUTE/WORK/sysroot install
   ```

2. Copy the container's real
   `/usr/lib/gcc-cross/mipsel-linux-gnu/9/libgcc_eh.a` to
   `WORK/gcc-unwind/libunwind.a`. Rust's static musl link requests this name.
   No unwinding functions are stubbed.

Then build:

```sh
python3 tools/spotify-offline/mips.py
```

It generates compiler/archiver/ranlib wrappers that run in a container with
networking disabled. Cargo and the Rust standard library are compiled on the
host. The resulting binary is under
`WORK/cross-smoke/target/mipsel-jooki-linux-musl/release/spotify_player`;
`WORK/mips-build.json` records the image, compiler, patches and binary hashes.
The helper does not install the binary or copy account credentials to a device.

## Integration status

The selected real playlist has downloaded successfully both on the development
computer and directly on the Jooki. All 18 entries fully decode in two new processes with networking denied. The original and
patched profiles pass the upstream checks. The MIPS binary also plays audibly on the
physical Jooki with its Internet route removed; see the [trial report](../../docs/33-spotify-offline-trial.md)
for exactly which device checks have been completed.

Figure control still needs a background player interface, complete playlist
generations, account separation/invalidation, storage limits and UI/status
integration. The fork downloads Ogg Vorbis music tracks, without a podcast or
lossless offline path. The original proprietary-SDK findings remain in the
[Spotify offline audit](../../docs/32-spotify-offline-audit.md).


## Application test package

The integrated candidate adds an opt-in web card with **Download for offline use**,
track progress, SD usage, ordered song lists and per-song playback. Modes are
**Online** (the original controller), **Automatic** (the last complete snapshot,
otherwise original online playback), and **Offline copy only**. Figure starts and
normal playback controls route to the optional backend. The original mode keeps
its existing account/Free behavior; this new backend requires Premium.

```sh
python3 tools/spotify-offline/mips.py
python3 tools/spotify-offline/package.py
python3 tools/spotify-offline/install.py \
  build/spotify-offline/test-version/openjooki-2.4.21-offline.1.tar.gz \
  --host DEVICE_IP --known-hosts /path/to/known_hosts
```

The last command is read-only: it checks every package checksum and the installed
OpenJooki 2.4.21/partition layout. Explicit `--apply` installs through the existing
A/B path and reboots. `--auth-cache /private/sdk/cache` optionally provisions the
separate already-authenticated SDK account; no browser pairing flow is included
in this test candidate. No credentials, music, keys or device backups are in the
archive. Keep any locally generated `private-backups/` private.

The SDK lives on the SD card at `/jooki/external/openjooki-offline`; an opt-in flag
`/data/openjooki/spotify-offline-enabled` enables it at startup. Installation keeps
the vendor daemon/binary and original presets. The saved install state contains
the previous A/B partition and SDK selection. Review or apply rollback with:

```sh
python3 tools/spotify-offline/install.py --host DEVICE_IP \
  --known-hosts /path/to/known_hosts --rollback --state /private/install-state.json
# Add --apply to perform that rollback and reboot.
```

The package is an **experimental application candidate**, not a replacement
kernel/bootloader image or a finished release. Cold offline reboot and physical
figure acceptance still need to pass. The implementation and exact validation
boundary are in [docs/34](../../docs/34-spotify-offline-test.md).
