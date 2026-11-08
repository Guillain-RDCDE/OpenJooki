# Spotify offline: feasibility audit

Audit date, including the live-device follow-up: **2026-11-08**. Overall SDK
offline capability: **unresolved**. The running controller and its embedded SDK
were inspected, but no usable persistent-storage/prefetch interface, matching
linkable SDK library or product enablement could be established. Offline
support is **not confirmed**, so the implementation gate remains closed.

The requested behaviour is the exact Spotify playlist assigned to a character,
fully synchronized in advance, playable without Internet, including after a
cold restart. Replacing it with uploaded audio files is outside this work.

## Decision

| Question | Result | Evidence / limit |
|---|---|---|
| Do the published and installed controllers implement persistent Spotify playlist downloads? | **Not supported by the current integration** | Both expose the same 15 transport/status commands, with no synchronization, download-progress or removal commands. The source has no SDK storage registration or prefetch calls. |
| Is the embedded SDK build offline-capable through a usable supported interface? | **Unresolved** | The installed SDK identifies as `3.163.106`; no storage/prefetch exports were found. One offline bandwidth-setting export does not establish persistent playback. Matching SDK headers and library are unavailable. |
| Is offline enabled for this client, product, device and account? | **Unresolved** | The live ZeroConf response confirms the source's client ID, product ID `32` and `streaming` scope, but supplies no affirmative offline capability or entitlement. |
| Can an extended Spotify controller be rebuilt with the available inputs? | **No, a required dependency is missing** | CMake requires the proprietary MIPS SDK static library, which is absent from the public archive. |
| Can the requested feature be delivered on the present evidence? | **No confirmed implementation path yet** | A matching offline-capable SDK and device verification are prerequisites. |

This is not a finding that every Spotify Embedded SDK build lacks offline
support, or proof that stripped internal code cannot contain such features.
It distinguishes the current streaming integration from unverified SDK
features and permissions.

## Inputs and reproducibility

The [official Jooki site](https://jooki.com/) links the
[2026-10-26 source archive](https://jooki.com/jooki-archive-20261026.tgz).
The local copy was checked against SHA-256:

```text
819293ee47d1b42439e50ad4d7f8f6180a6feabf2ff28595dbc45c2cc33706fc
```

The controller files below are relative to
`jooki-archive-20261026/ml-yocto-jooki/sw/controllers/spotify_ctrl/` in that
archive. The audit reads the original archive, independently of other firmware
patches in a prepared build directory.

| Input | SHA-256 |
|---|---|
| `spotify_ctrl.c` | `a571f352fc4f500a5391e2a73d5761830f14f31c27655727bbfaf0dc7894f407` |
| `spotify_embedded.h` | `1756d907db9d4235e7392750d5c991011b04f214858677b388c3e03ae49e3cba` |
| `CMakeLists.txt` | `010cac9cd7aff0f81dfbde0a9ab63ef07431a25a1ae0660bb8815979308d2467` |

Reproduce the source inventory with Python 3, without extraction, network
access, an SDK installation or device access:

```sh
python3 tools/openjooki/spotify_offline_audit.py build/firmware/jooki-archive-20261026.tgz
python3 -m unittest discover -s tools/openjooki/tests -p test_spotify_offline_audit.py -v
```

Supply the downloaded archive's location if it is elsewhere. The tool verifies
the archive checksum and emits JSON including per-file checksums. Its result
remains `unresolved`: finding a declaration, callback name, error constant or
library file cannot establish offline support. It inventories names, not SDK
semantics, compiled features or product permissions. The tests use synthetic
sources and check these false-positive cases and read-only archive handling.
No Spotify code, binaries, credentials or device identifiers are added to Git.

## Controller, SDK and storage findings

The published Linux service is `spotify_ctrl`, installed at
`/jooki/bin/spotify_ctrl`. This is separate from the ESP32 firmware. Rebuilding
the ESP32 with a public Espressif SDK does not supply the Spotify library.

`spotify_ctrl.c:28` declares **eSDK `v3.156.25`**; the header declares
**`SP_API_VERSION 63`**. The device follow-up established that the wrapper's
version label is stale: the embedded library identifies as **`3.163.106`**
(see below). The API version is the published header's identifier, not a
measurement of the installed SDK's complete interface.
`ml-j2000/machine.h` selects model **J2000**.

The initialization uses brand `Jooki`, model `J2000`, product ID `32`, the
published client ID, `streaming` scope and `read_mac()` for the unique device ID.
The header describes the client/product pair as a backend product identifier.
It also ties saved credentials to the unique ID. None of these fields proves
offline enablement; changing them would not establish it.

The header has **65 public function declarations**. Manual inspection of the
configuration, callback structures and declarations found no interface to
register persistent audio storage, synchronize a playlist, query its download
completion or remove its stored audio. The name inventory likewise finds no
offline, storage, cache or prefetch function declarations or callback types.

Five error constants mention prefetch or storage, including
`kSpAlreadyPrefetching`, `kSpStorageReadError`, `kSpStorageWriteError` and
`kSpPrefetchDownloadFailed`. Their comments explicitly limit their relevance
to builds with offline storage enabled. They do **not** establish that this is
such a build. The header's reference to offline blob login also does not
establish that playlist audio and its playback context persist.

The controller registers connection, playback and debug callbacks, with no
persistent audio storage callbacks. Its 15 MQTT commands cover transport,
volume, shuffle/repeat, presets, logout, output selection, connectivity and
status. There are no synchronization, download-progress or stored-playlist
removal commands.

Three existing mechanisms need to be distinguished from a playlist download:

- **RAM buffering.** `SP_MEMORY_BLOCK_SIZE` is `1024*1024*1`; it is passed to
  `SpConfig.memory_block_size`, with low playback bitrate. It is volatile.
  Spotify documents this as buffering for short network outages, not durable
  storage. [Spotify's buffering FAQ](https://developer.spotify.com/documentation/commercial-hardware/implementation/faqs#how-much-audio-data-does-the-esdk-buffer)
- **Presets and resume state.** `SpPresetSubscribe` / `SpPlayPreset` preserve
  context and playback information. OpenJooki stores a playlist's URI/preset
  and, for resume, its position. Those records contain no downloaded audio.
  The direct-start patch in `tools/openjooki/spotify_direct.py` only selects
  a context, track and position; it adds no storage capability.
- **Saved login.** `/data/spotify/credentials.bin` allows a later login. It is
  not a track cache. It was not read or copied during this audit.

## Live-device findings

After the device was powered on, read-only SSH succeeded on its existing
**port 22**. Maintenance SSH on 2222 was closed and was not enabled. The
running system reports OpenJooki **2.4.21** on MIPS; the running process's
executable is `/jooki/bin/spotify_ctrl`.

Both executables were copied privately into ignored
`build/spotify-offline/device/` for local analysis:

| Executable | Bytes | SHA-256 |
|---|---|---|
| Installed `spotify_ctrl` | 596308 | `0a16443bb6c95ad1f5d6dd9d53c6c0e9defa4dda436bc9ad2efb48cbf45a432c` |
| Preserved `spotify_ctrl.openjooki-orig` | 596308 | `a043029f5fde6c987cf21c6d1aedaf1db11525196bc3962955cd5831b9a15ab8` |

Applying the existing `spotify_direct.patch()` to the original copy produces
the installed executable byte for byte. Only its 164-byte MQTT handler region
differs; the embedded SDK code is identical in both copies.

The executable is **ELF32 little-endian MIPS32r2**, stripped, with build ID
`9d14a6288eea7b494703c6b1968d3d03f0db682a`. Its dynamic dependencies are
`libmosquitto.so.1`, `libasound.so.2` and `libc.so`; process mappings likewise
show no separate Spotify shared library. The Spotify SDK is embedded in the
controller executable, rather than supplied as a separately loaded library.

The embedded SDK version was established from the getter, rather than by
selecting a version-looking string: `SpGetLibraryVersion` at `0x0040acfc`
branches to `0x00411bfc`, whose return path resolves to the string at
`0x00473a50`: **`HEAD-v3.163.106-ge3123edf`**. ELF load-segment mappings,
MIPS instructions and GOT entries were checked against the copied file. The
wrapper's independent `v3.156.25` log string remains in the same executable.
No code was injected and no debugger called SDK functions inside the running
process.

A read-only request to the existing Spotify ZeroConf endpoint,
`GET /zc?action=getInfo` on port 8080, independently confirmed the running
service's `libraryVersion` as **`3.163.106-ge3123edf`**, with `statusString=OK`
and `spotifyError=0`. It reports brand/model `Jooki` / `J2000`, product ID `32`,
`streaming` scope and a client ID matching the published source. The response
has an empty `availability` field and no affirmative offline capability. Its
separate `version` field is `2.9.0`; the SDK identity is taken from
`libraryVersion`.
Only non-personal fields were retained locally; device identifiers and keys
were not copied into the report or repository.

The dynamic symbol table contains **79 defined `Sp*` functions**, including
the wrapper's audio helper. There are **no exported functions with prefetch,
storage or cache in their names**. The only offline-named export is
`SpOfflineBandwidthLimitingDutyCycleSetTime` at `0x00419884`. Disassembly shows
a command-dispatch path, not a trivial disabled stub, but its presence does
not establish storage callbacks, playlist downloading, progress, removal or
persistence. It is absent from the published header and is not called by the
published wrapper. Internal strings mentioning prefetch, offline requests and
memory caches also provide no usable storage contract or entitlement proof.
Because the executable is stripped, absence from its dynamic symbol table is
not proof that an internal feature is absent.

The installed executable contains the same **15 MQTT command names** as the
published source. There is no exposed offline synchronization interface to
connect to the core or web UI.

Storage measurements at the time of the audit:

| Location | Observation |
|---|---|
| `/data/spotify` | Only `credentials.bin` (2117 bytes); 4 KiB directory usage. The file's contents were not read. |
| `/data` | 42706 KiB available on `/dev/mmcblk0p5` (about 41.7 MiB). |
| `/jooki/external` | 5027596 KiB available on `/dev/mmcblk0p7` (about 4.79 GiB). |
| Controller's open file descriptors | Audio devices, sockets, console, random source and device-ID file; no open audio-cache file at that instant. No device-ID file contents were read. |

These observations establish present storage use and available SD-card space;
they do not prove what a different SDK build could store. No daemon was
restarted, configuration changed, playback started, Internet disconnected,
device rebooted or firmware written during the audit.

## Rebuild and remaining SDK limits

`CMakeLists.txt` links
`spotify_ctrl/${MACHINE}/libspotify_embedded_static.a`; for this device the
required file is `ml-j2000/libspotify_embedded_static.a`. It is absent from the
archive. The controller's README and the archive's `README-repos.md` explicitly
say the library was removed and must be obtained separately from Spotify.
The device search under `/jooki`, `/usr/lib` and `/lib` found the controller,
its preserved original, the direct-start marker and UI artwork, but no
separate Spotify SDK library. The copied stripped executable does not supply
the matching SDK headers or linkable static library required by this build.

Consequently, a usable extended controller cannot currently be linked.
Compiling it against invented declarations or stub functions would not resolve
this dependency. Spotify's current documentation directs SDK distribution
through its partner build system; it does not identify the installed Jooki
build's features. [SDK distribution FAQ](https://developer.spotify.com/documentation/commercial-hardware/implementation/faqs#where-can-i-download-the-esdk-builds)

The earlier source-only audit could not reach the powered-off device. The
follow-up above resolves device access, executable identity, SDK version and
available storage. Compiled offline feature availability through a supported
SDK interface, client/product/device/account enablement and actual playback
after an offline restart remain unverified.

To reopen the implementation gate, obtain and inspect the matching MIPS SDK
library, its storage/prefetch documentation and headers; establish that the
necessary features are compiled and enabled for the actual product/device and
account; and link a controller against that SDK. A device trial must then
demonstrate persistent playback through the documented storage interface.

## Implementation and acceptance after the gate opens

Concrete SDK calls and web/core commands remain undefined until those
interfaces are identified. The eventual implementation must:

- Synchronize the exact character-linked playlist, report completion and
  storage use, and remove saved playlists through supported SDK operations.
- Use SDK-managed persistent storage on the SD card for audio and required
  playback data. Preserve the exact synchronized playlist membership and
  order, including duplicate tracks; do not silently substitute another list.
- Publish a new synchronized generation only when all required data is
  durable and the SDK reports completion. A failed or interrupted update
  retains the last complete generation; the UI shows the incomplete state.
- Keep saved generations bound to the proper account and device. Account
  changes must invalidate access to the previous account's offline content
  and follow the SDK's removal and authorization rules.
- Start that complete generation from the figure without Internet or a phone,
  including after restart. Add “Make available offline”, download status and
  storage use only when they describe a working capability.

The acceptance matrix is prepared but **none of these device tests has run**:

| Test | Required observation |
|---|---|
| Synchronize, disconnect Internet, place figure | Every track of the exact completed snapshot plays in its saved order. |
| Next/previous and seek while offline | Track changes and seeking work throughout the synchronized playlist. |
| Power off, keep Internet disconnected, restart, place same figure | The same complete generation plays without an online initialization. |
| Interrupt download and restart | Partial content is not reported as ready; the last complete generation remains usable. |
| Fill storage during an initial download and an update | A clear failure is reported, completion stays false, and an existing complete generation survives. |
| Change account | The previous account's content cannot play as the new account; synchronization follows SDK authorization. |
| Edit the online playlist after synchronization | Offline playback remains the last complete snapshot until a new synchronization completes. |

This audit adds no runtime offline API or download UI. The prerequisite is a
verified suitable Spotify integration; the source-only findings cannot replace
that prerequisite.
