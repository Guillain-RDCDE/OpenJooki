# Experimental Spotify offline player trial

Trial date: **2026-11-08**. The selected alternative is
[CormAlan/spotify-player-offline-mode](https://github.com/CormAlan/spotify-player-offline-mode),
an independent application based on librespot, pinned to
`cd47e7594b2f564c52a07751c6c4b0f27b26af06`.
Its binary reports `spotify_player 0.25.1-offline.1`.

**Result:** real Spotify downloads made on the development computer persist on
the SD card and play on the physical Jooki. All 18 tracks pass local decoding
and seek/restart probes on the hardware with its Internet route removed. The
user confirmed audible playback during the longer offline listening test.
Figure control, core/web UI integration and a cold offline reboot remain open.
This independent application is an experimental alternative; the original
proprietary SDK's offline capabilities remain unresolved in the
[original audit](32-spotify-offline-audit.md).

## Real playlist trial

The user confirmed Premium and selected an existing figure's playlist. Its URI
was read from the device's playlist catalog; the original Spotify credentials
were not read or imported. Browser OAuth authenticated the trial separately.
The exact selected URI and track order are retained privately under ignored
`build/spotify-offline/trial/private/`.

- All **18 tracks** downloaded successfully, with **36,540,203 encrypted audio
  bytes** and **3,204 seconds** of music in total.
- Every track fully decoded in **two fresh processes with networking denied by
  macOS `sandbox-exec`**, using only the persisted files and keys.
- Initial decoding, seeking to each track's middle and returning to its start
  also pass for all 18 tracks with the bounded reader.
- The completeness helper checks the ordered playlist manifest against the
  downloaded inventory and refuses empty or missing selections. It records
  binary/patch hashes and rejects a binary changed during verification.

These are real account/download results; the generated-silence fixture is
separate engineering test data, not a replacement playlist for the figure.
No actual music, authentication tokens or playback keys are in Git.

## Source changes and checks

The original pinned source builds on macOS with Rust/Cargo **1.99.1**, using
`--locked --no-default-features --features rodio-backend,rustls-tls`.
All **50 baseline tests** pass; the full desktop feature set passes **51**.
The checked trial adds these reviewable patches:

- **Authentication:** use the ncspot app's current `/ncspot_login` callback
  for both its primary and fallback Web API branches. The original trial
  returned `redirect_uri: Not matching configuration`. This follows
  [upstream's correction](https://github.com/aome510/spotify-player/pull/1108)
  and covers the default-client branch too. The streaming callback stays
  `/login`.
- **Bounded audio I/O:** downloads spool to private temporary files; checksums
  are computed in 8 KiB chunks; AES decryption and Vorbis decoding read seekable
  file regions. The 167-byte Spotify prefix and `.spdl` metadata are excluded
  from the decoder's position space. No whole-track encrypted/decrypted copies
  are allocated. Failed replacements retain the old file.
- **Probe command:** `downloads probe URI` checks local integrity, decoding
  and seeking without an audio output device. Timed `--headless` playback starts
  without terminal setup, stops after 1–300 seconds and reports JSON status or
  an audio error. The fork's own README and offline/configuration docs describe
  these changes. Output contains public metadata only.
- **MIPS transport profile:** use Rustls/WebPKI for librespot, rspotify and
  reqwest, retaining TLS certificate verification without target OpenSSL.

The final patched profile passes formatting, **52 full-feature tests**, and
Clippy with warnings denied both with the full desktop feature set and with no
features. The new region test covers offset-relative seeking, bounds, EOF and
neighbouring-data isolation; the encrypted round-trip test checks seeking after
reopening. Corruption and failed-replacement tests continue to pass.

The native synthetic-silence check also lists and decodes seven audio packets
in two new processes under network denial. Reproduction commands, source
patches and build helpers are in
[tools/spotify-offline/](../tools/spotify-offline/README.md).

## MIPS and physical device

The installed Jooki uses MIPS32r2 o32 with hard-float/32-bit floating-point
registers. Rust's built-in musl target is tier 3 and defaults to soft float.
The trial supplies a matching experimental target and rebuilds the standard
library from the installed compiler's matching sources.

The static cross-build uses local Docker image
`openjooki-firmware-port-tools:local`, ID
`sha256:3f1dce4bf3900437b5729cb99c15bdcb07108a3a1f207c061479b32268a89805`,
with GCC **9.4**, musl **1.2.3**, real GCC exception-unwinding code and statically
built ALSA **1.2.14**. No SDK or unwind functions are stubbed. The full player
passes version/list/decode checks in QEMU `24Kf` with the container network
disabled.

The initial 18,862,720-byte player, SHA-256
`c95a939d2ff4fa51b655a4ecdfca894861d29b6ee16695b7924e505fb7417120`,
was copied into a new isolated SD-card trial directory. Transfer integrity was
checked before execution. On the physical Jooki it reports its version, lists
the synthetic fixture, and decodes all seven packets in two new processes,
under a **4 MiB data limit**, 512 KiB stack limit and 64 MiB virtual-address
limit. The three existing player/controller processes kept the same PIDs.

That first device check was conducted while the device remained connected.
The kernel rejects both a separate network namespace and the attempted
per-child seccomp filter with `EINVAL`; neither mechanism is presented as a
successful device network-isolation test. Wi-Fi/firewall settings were not
changed. QEMU and macOS isolation results are recorded separately.

The bounded build (18,883,200 bytes, SHA-256
`3b567dbc93a2c9094e9390ac17a3dcb86da264781ed93dbe7f76e3a465c24f96`)
and all 18 selected real tracks were copied to a separate SD-card directory.
**All 18 initial/middle/restart probes pass on the physical Jooki** under the
same 4 MiB data limit. Initial and restarted packets are at 0 ms; requested
middle positions are reached within 21 ms. The existing daemon PIDs remain
unchanged and available memory is 10,952 KiB after the run. Transfer plus probe
execution takes 206.3 seconds; this is not a standalone decoder benchmark.
The same MIPS build also passes all 18 probes in two fresh QEMU processes with
container networking disabled and an empty separate credentials cache.

The interactive player exits with `Not a tty` over the device SSH PTY. A timed
`downloads play URI --headless --duration 20` path therefore uses the same audio
worker without terminal setup; it reports final JSON status and audio errors.
It does not yet provide a remote control interface.

The headless build (18,891,396 bytes, SHA-256
`90019ea943a055d04fa348803862c86b22a23d4bfd46cdd1c0dac0936b558a99`)
passes a synthetic ALSA-null output test in network-isolated QEMU. A corrupt
payload produces a checksum failure and terminates the worker cleanly. On the
physical Jooki, a **20-second output test** of the selected playlist exits 0,
reports no audio error, and reaches position **19,475 ms** at volume 20%. At a
3-second snapshot, RSS is **2,588 KiB**, its high-water mark is **4,392 KiB**,
data size is **3,656 KiB**, and swap use is zero. This playback test uses an
8 MiB data limit to allow its worker thread. Existing daemon PIDs are unchanged.
The user requested a repeat and **confirmed audible music** during a second
30-second hardware run. That run exits 0 at **29,482 ms** with no output error,
RSS 2,792 KiB, high-water mark 4,084 KiB, data 3,652 KiB and no swap at its
3-second snapshot. Both runs stop automatically.

For the device Internet-disconnection test, the single default IPv4 route was
removed temporarily while the directly connected LAN/SSH route was preserved;
IPv6 is absent on the device. A control ping failed with `Network unreachable`.
A new 30-second playback process exited 0 at 29,482 ms, with the route absent at
all five-second checks. A separate new process then passed decoding and seeking
for **all 18 tracks** under the 4 MiB data limit while that route was removed.
Each test restored the original default route, with an independent delayed
restoration watchdog as fallback. Existing controller/player PIDs stayed the
same. The user requested a longer repeat and confirmed audible music during
the 60-second offline run. It exits 0 at **59,313 ms** and restores the
original route. ALSA reports one recovered underrun during this longer run;
extended playback stability still needs work. This tests Internet loss, not a cold device boot or figure trigger.

Private manifests/results stay under ignored `build/spotify-offline/trial/`.

## Direct on-device synchronization

The same MIPS build also authenticates and downloads on the Jooki itself. This
uses a separate private trial directory and the already authorized trial
account's credentials/tokens, copied with owner-only permissions. The original
controller's credentials are untouched. First a selected real track downloads
and passes decode/seek checks directly on the device in 17.6 seconds.

Then **all 18 tracks of the exact selected playlist synchronize directly on the
Jooki**, with matching playlist order, in **248.7 seconds** including subsequent
probes. Every track passes initial/middle/restart decoding in a new process.
Synchronization is bounded to 16 MiB of data and verification to 4 MiB; the
existing player/controller PIDs remain unchanged. This demonstrates the SDK
transport/authentication/download path on the actual MIPS hardware as well as
its independent offline playback path. The test account is not a finished
web-based pairing or account-management flow.

## Remaining requirements for figure integration

The fork is an application with an interactive offline player. Before offering
an offline button or promising the figure goal, the integration still needs:

- A background control interface for figure, transport and status commands;
  the existing offline mode is separate from the ordinary daemon/socket path.
- Complete, durable playlist generations. Upstream skips missing collection
  files and can publish a manifest after individual downloads fail. A figure
  must retain the previous complete generation until an update is verified.
- Account separation and invalidation. Stored headers contain playback keys
  but no account identity, and the separate trial login is not yet a Jooki
  account-management integration.
- Download progress/failures, capacity limits, removal and core/web UI status.
- Web-based account pairing/management, extended hardware playback and
  resource/performance measurements, figure/transport control, a cold offline
  reboot, interrupted downloads, full storage and account changes.

The current download implementation supports Ogg Vorbis music tracks; podcasts
and lossless offline playback are not implemented. The original proprietary
SDK's offline capabilities remain unresolved independently of this trial.
