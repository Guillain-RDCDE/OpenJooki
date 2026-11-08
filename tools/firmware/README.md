# Jooki 2 volume firmware work

**Status, 2026-11-08: the public-SDK port builds a complete ESP32 image.**
The static MIPS controller also builds reproducibly. A complete original ESP32
backup and cold UART restoration have been physically verified on a Jooki 2.
An earlier API 1 port booted and passed preliminary device checks, then stock
was restored. The global-scale API 2 image also passed its guarded device trial: real volume
acknowledgments, limits, mute/fade and reboot. The owner confirmed audible speaker
control and physical wheel takeover. Headphones and Bluetooth audio remain untested.

The archive-only SDK reconstruction (`--sdk`) still lacks two APIs. The new
`--public-sdk` path instead uses public ESP-IDF **v4.4.3**, commit
`6407ecb3f8d2cc07c4c230e7e64f2046af5c86f7`, with matching Wi-Fi headers and
libraries. `esp-idf-v4.4.3.patch` preserves the released Jooki customisations on
that base. `sdk-port.patch` and `port/sdio_tx.h` replace the private SDIO transmit
call with the public bounded queue/completion API and explicit DMA ownership.
The ADF build patch resolves its version from the pinned ADF tree; the build
fixes Python's hash seed because the SDK linker generator iterates sets.
The application descriptor is explicitly `0x020C-oj-volume2`; it does not depend
on an enclosing Git repository. The published BLE scan cache and provisioning
behaviour are explicit in the port profile, including no new BLE bonding requirement.

The [volume report](../../docs/30-volume-controls.md) and
[public-SDK port report](../../docs/31-public-sdk-port.md) record verification
and the physical recovery evidence and remaining device checks.

The source is the [official archive](https://jooki.com/jooki-archive-20261026.tgz),
SHA-256 `819293ee47d1b42439e50ad4d7f8f6180a6feabf2ff28595dbc45c2cc33706fc`.
`volume.patch` contains the source changes, including both protocol endpoints.
Source trees, toolchains and binaries stay under ignored `build/` or outside Git.

## Contract

Existing protobuf enum values and field numbers remain unchanged. The additions:

* `TypeCmdSetVolume = 86`, `TypeRespSetVolume = 87`; payload tags 92 and 93.
* Request: integer `percent` 0–100, `maximum_plus_one` 0–101. Zero omits a new
  ceiling and retains the previous one; 1 encodes a ceiling of 0%, 101 one of 100%.
  The offset represents optional presence without requiring a newer proto3 compiler.
* Response: `result = 0` for success, a nonzero error otherwise.
* `GetKnobsState.volume_api = 2` at field 4 advertises the shared global curve.
  An old response decodes as 0; the earlier relative-scale trial used 1. The
  controller and core issue global SetVolume only after capability 2.
* MQTT command `/j/esp32/output/audio/set_volume` takes
  `{"percent":80,"maximum":35}` (maximum optional). Its result is published as
  `0` or `-1` on `/j/esp32/input/audio/volume`.
* `/j/esp32/input/knobs/state` adds `volume_api`. Its existing `volume` remains the
  physical dial position. The core keeps that position separately from saved volume.

The ESP32 arbitrates host requests and actual dial movement under its volume
semaphore. SetVolume opts into the normal global curve, replacing the fixed
kids multiplier. Existing SetToysafe commands select the legacy factory curve.
Periodic work reapplies the selected value and hardware mute. The ceiling constrains
local dial changes before Linux responds. Endpoint rounding agrees between
polling and notifications; the ADC filter is initialized from the first sample
and averages all taps instead of repeatedly using one tap.

## Native checks (no SDK or hardware)

From the repository root, with `cc`, `protoc-c`, the protobuf-c development library
and Python 3 installed:

```sh
python3 tools/firmware/prepare.py --port --out build/firmware/port-check
python3 tools/firmware/test.py build/firmware/port-check/jooki-archive-20261026 --archive build/firmware/jooki-archive-20261026.tgz
python3 tools/firmware/test_gain.py build/firmware/port-check/jooki-archive-20261026
python3 tools/firmware/test_sdk.py build/firmware/port-check/jooki-archive-20261026
```

The test compares every old message number and field tag to the pinned archive,
compiles/runs the actual volume arbiter and request parser, and runs the actual
Linux command codec against a serial peer with old/new capability responses,
zero/omitted ceilings, malformed replies, errors and missing responses. The codec
test uses AddressSanitizer and UndefinedBehaviorSanitizer. The SDIO suite extracts
the actual patched transmit and reset functions and tests timeouts, late tokens,
DMA buffer preservation, capacity checks, tick wrap and reset failures with the
same sanitizers. The gain suite compiles the actual ESP32 audio functions and
checks all 101 values on both modes, including the factory-equivalent default.
CI runs all three suites. Driver fault injection does not simulate
physical SDIO timing or prove compatibility with the Linux driver.

## Cross builds

The container pins Ubuntu 20.04 by digest and uses Linux amd64 for the ESP32
toolchain. SDK bases, patches, submodule commits, toolchain download hashes (IDF's
`tools.json`), Python constraints and MIPS library archives are pinned. Use a
consistent `/src` path and `SOURCE_DATE_EPOCH` for byte comparisons.

```sh
python3 tools/firmware/prepare.py --public-sdk --out build/firmware/public-source
python3 tools/firmware/fetch_mips_deps.py build/firmware/public-source/jooki-archive-20261026
docker build --platform linux/amd64 -t openjooki-firmware tools/firmware
docker run --rm --platform linux/amd64 -v "$PWD:/work:ro" -v "$PWD/build/firmware/public-source/jooki-archive-20261026:/src" -v oj-mips-deps:/opt/oj-mips openjooki-firmware bash /work/tools/firmware/build_mips.sh
docker run --rm --platform linux/amd64 -v "$PWD:/work:ro" -v "$PWD/build/firmware/public-source/jooki-archive-20261026:/src" -v oj-esp-tools:/root/.espressif openjooki-firmware bash /work/tools/firmware/build_esp32.sh
```

`prepare.py --public-sdk` applies all source patches strictly and fetches each
submodule at its pinned commit. The public-SDK patch retains Jooki's Bluetooth
and SDIO receive fixes, preserves the newer SDK's Bluetooth polling field and
uses a correctly typed Bluetooth-address copy for connection-request events.
The old `--sdk` mode is retained solely to reproduce the archive's incomplete
SDK; it is not the ported build. An existing source directory with different
patches is rejected: use a fresh `--out` rather than mixing variants.

The SDIO port uses a single 500 ms budget for mutex acquisition, queueing and
completion. A timed-out transfer retains its DMA buffer; the next write first
waits for the exact token. Reset stops DMA, flushes and verifies that token,
then restarts, with bounded locks and RX polling. Invalid tokens or failed
resets leave transmission blocked until recovery. Oversized packets are rejected
before copying, fixing the archive's unsafe truncation-then-full-copy path.

The MIPS build uses musl 1.2.3, protobuf-c 1.3.3 and Mosquitto 1.6.12, with
MIPS32r2 / hard float / 32-bit FPU registers matching the original controller's
ELF attributes. The controller is static: it does not require newer shared
libraries on the Jooki. Its local MQTT connection does not use TLS. Two rebuilds
produced the same 379032-byte binary, SHA-256:
`f194a890bd097cb0b54b901f552a4d916a4fb7c6204947b2c20fb7d80a5a337f`.
This API 2 controller ran on the Jooki during the guarded speaker-volume trial.

## Packaging and recovery gate

After a successful, verified ESP32 build:

```sh
python3 tools/firmware/package.py build build/firmware/public-source/jooki-archive-20261026/esp32-code/jooki_v2/build build/firmware/factory_default_firmware.tgz
python3 tools/firmware/package.py check build/firmware/factory_default_firmware.tgz
```

Packaging is deterministic, follows the build's flash arguments, includes all
four flash regions and a device-compatible `esp32/flash.sh`, and rejects unsafe
paths, unknown layouts and overlapping regions. It never flashes anything.

Before any device test, preserve the original **device's**
`/etc/esp32/factory_default_firmware.tgz`, controller and installer script outside
Git. The tested OpenJooki 2.4.21 device reported ESP32 firmware 524 (0x020c), API
0x0204. Its original package SHA-256 was
`7af7a71f682aa410a43fe2c091094380abd449cc33ef5eb4efe0ccd1e2ed8c53`.
It differs from the older MP2107A reference image in the source archive.

The backup was compared with the device's SHA-256; its four regions and flash
script pass `package.py check --sha256 <original-hash>`. Espressif's image parser
validated the bootloader and application checksums and appended SHA-256 digests.
The rebuilt partition table matches the device backup. Repacking twice produced
identical packages. These package checks alone do not establish a physical restore.

The device installer `/usr/bin/ml-esp32-install-firmware.sh` lowers Wi-Fi, unloads
SDIO, changes `esp_reset` / `esp_bootmode`, then runs the package's `flash.sh` on
`/dev/ttyS0`. Flashing can therefore remove the network connection. A verified
recovery path must work without relying on the newly flashed ESP32's Wi-Fi.
Linux A/B rollback alone does not restore ESP32 flash or its NVS. Keep the original
package on a recoverable card and verify the complete restore process before any
new firmware is installed.

On the test device, a private full 16 MiB backup was compared with the actual
stock app and partition table. A cold early-boot recovery restored and verified
the bootloader, partition table, NVS, PHY and complete OTA0 slot (0..0x610000)
through the ROM UART loader, before loading SDIO. All 25 recovery chunks passed
device MD5 verification and the stock Wi-Fi/core returned. An independent offline
watchdog requests that same cold recovery if a candidate fails. No eFuse or
security setting is written. The full backup contains private settings and is
kept outside Git. See the SDK report for remaining hardware coverage.
