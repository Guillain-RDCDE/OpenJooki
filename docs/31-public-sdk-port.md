# Jooki 2 public SDK port

Status on 2026-11-08: a complete ESP32 firmware image builds from public sources.
Two independent complete builds produce identical images and ELF files.
Original recovery has been physically rehearsed; an earlier API 1 trial booted
and passed preliminary controller checks, then stock was restored. The global-scale API 2 image subsequently passed its guarded speaker-volume
trial, including a full reboot. The owner confirmed audible web volume and wheel
takeover; wired headphones and Bluetooth audio have not been checked.

## Sources and changes

- Official Jooki archive, SHA-256
  `819293ee47d1b42439e50ad4d7f8f6180a6feabf2ff28595dbc45c2cc33706fc`.
- ESP-ADF base `84c541bf8e7c6e8755fb2b77aa376352be6662f2`, with the archive's
  source patches and a small build-directory/version fix.
- Public ESP-IDF v4.4.3, commit
  `6407ecb3f8d2cc07c4c230e7e64f2046af5c86f7`. Wi-Fi headers and binary libraries
  are fetched together from this pinned release.
- Jooki's released IDF changes are rebased in
  `tools/firmware/esp-idf-v4.4.3.patch`. The newer Bluetooth polling field is
  retained; connection-request addresses are copied into the expected type.
- `tools/firmware/sdk-port.patch` and `port/sdio_tx.h` replace the unavailable
  private SDIO transmit function using public driver operations. The versioned
  SDK defaults preserve the published BLE scan cache and keep provisioning
  without a new BLE bonding requirement.

Prepare/build commands, pinned container and Python dependencies:
[firmware README](../tools/firmware/README.md). The archive-only `--sdk` variant
is retained for comparison; use `--public-sdk` for the working port. All
submodules stay pinned; no compiler error is suppressed and no SDK API is stubbed.

## SDIO ownership and recovery

The public driver retains ownership after a transfer is queued. A completion
timeout does not cancel DMA. The port retains the single preallocated TX buffer
until the exact completion token returns; repeated writes cannot overwrite it.
There is one 500 ms waiting budget across TX mutex, queue and completion, using
FreeRTOS's timeout accounting, including tick wrap.

A reset obtains write/TX/RX locks in that order, stops the peripheral, performs
the driver reset, verifies the flushed token and only then restarts. RX polls
at 50 ms so that it yields its lock for reset. Reset locks are bounded; failed
reset/start or invalid tokens block transmission until recovery. No dynamic TX
allocation is introduced. Packets exceeding the fixed buffer capacity are
rejected before copying; the original truncation path still copied the full
payload and could overrun the buffer.

The driver ownership contract is documented in
[Espressif's SDIO guide](https://docs.espressif.com/projects/esp-idf/en/v4.4.3/esp32/api-reference/peripherals/sdio_slave.html).

## Verification

- Complete ESP32 application, bootloader, partition table and OTA metadata build.
  Independent source preparations, regenerated configurations and complete builds
  produce byte-for-byte identical results, including the ELF. The package also
  reproduces byte-for-byte.
- Native tests extract and compile the actual patched transmit/reset bodies:
  packet packing/checksum, exact capacity, oversized/null inputs, completion
  timeout and late completion, one combined 500 ms budget, tick wrap, queue and
  mutex failures, mismatched tokens, reset ordering and failed-reset recovery.
  They pass with AddressSanitizer and UndefinedBehaviorSanitizer.
- All volume values/ceilings 0–100, startup orders, mute and actual Linux protobuf
  codec failure paths pass the existing native tests; old wire tags are retained.
- 341 Lua specs pass on the isolated volume branch. The integrated real-core/MQTT/browser checks and backend,
  bedtime, parent-code, UPnP and lights regressions cover the companion Linux/UI
  changes; they do not establish physical ESP32 behaviour.
- The MIPS controller rebuild retains SHA-256
  `f194a890bd097cb0b54b901f552a4d916a4fb7c6204947b2c20fb7d80a5a337f`.
- ESP32 application and bootloader pass esptool checksum/hash validation.
  The candidate partition table is byte-for-byte identical to the device backup.
- Original recovery-package digest and flash-layout validation still pass.
- The ELF links the real Wi-Fi PMF function and has no private SDIO transmit
  dependency. Four unused `-u` hints from the public SDK remain in its symbol
  table for renamed/disabled helpers; the real startup functions are linked and
  the final ELF has no remaining relocations. These names are recorded in the
  local artifact manifest.
- The image fits the original 6 MiB application slot. Static IRAM uses 124114
  bytes with 6958 remaining; static DRAM uses 40968 bytes with 83612 remaining.

The first repeat exposed nondeterministic linker fragment ordering. The build
fixes `PYTHONHASHSEED=0`, `SOURCE_DATE_EPOCH` and `TZ`, and obtains ADF version
metadata from the actual ADF checkout rather than an enclosing repository.
The application descriptor is fixed to `0x020C-oj-volume2`; the on-wire
manufacturer firmware number stays `0x020C` and the new volume API is advertised
separately. The companion OpenJooki version remains 2.4.21.

## Device gate

The original full 16 MiB flash backup was independently checked against the
stock application and partition table. Its SHA-256 is
`8ddb89903371ea7ebc63a6cc900f2c02d3dd33685558614de864be6f4a7c1812`.
A cold early-boot rehearsal restored the first 0x610000 bytes (bootloader,
partition table, NVS, PHY and full OTA0 slot); all 25 UART writes passed device
hash verification. The device returned on its known Linux partition with the
stock ESP32 firmware. Candidate writes touch only regions inside that prefix;
OTA1 and the immutable tones tail remain unchanged. The complete backup is
private because it contains device/network settings.

The trial runs with an early recovery hook and independent offline watchdog.
A failed or unexpected reboot selects the known Linux root and restores ESP32
before loading SDIO, without depending on candidate Wi-Fi. Linux A/B rollback
alone remains insufficient. Read-only checks confirmed no secure boot or flash
encryption on this specific device; no eFuses or security settings were changed.

The earlier API 1 image booted, returned capability and successful volume replies,
kept web volume through unchanged real wheel reports, and applied parent limits.
That trial was rolled back before adopting a single global scale. API 2 passed real volume acknowledgments at 0/10/20, eight unchanged physical
wheel reports retaining a web request, parent ceilings 0/7/100, kids-mode gating,
combined night/parent limits, invalid-input rejection, mute/unmute, sleep fade and
a complete reboot preserving volume/limits. The owner confirmed audible speaker
control and real wheel takeover. Full wired-headphone/Bluetooth, provisioning and
NFC/charging-transition coverage remains outstanding. The trial was accepted on
the device; this is not a public firmware release.

Local candidate package SHA-256:
`42921d6ed3abfa432f0cfe4a9d1394148a39c9d1080dd6f6a6e9fd9e540bd62c`.
The local candidate and its source/artifact manifest are under
`build/sdk-port/candidate-2.4.21/`; these binaries are not committed or published.
