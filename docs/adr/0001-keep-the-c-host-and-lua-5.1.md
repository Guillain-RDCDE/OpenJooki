# ADR-0001 — Keep the C host and Lua 5.1 for the 2.0 core

Status: proposed (2026-09-26)

## Context
The Jooki's application is loaded by a closed C program (`/jooki/bin/player`)
that expects a zlib-compressed Lua 5.1 chunk of at most 200 KiB and provides
four functions (ALSA volume, syslog, terminating flag, sd_notify). We can
replace any file on the root partition through our A/B images, so we could
also ship our own host binary (MIPS32 little-endian, musl).

## Decision
2.0 is a Lua 5.1 program loaded by the existing host. The host's four
functions are used only through `adapters.host`, so the core does not depend
on them beyond that file.

## Alternatives
- **Our own host binary (C, Go, Rust)**: full control (Lua 5.4 or no Lua,
  threads, native JSON/MQTT), but a cross-compilation toolchain to maintain,
  a second thing to test on the device, and a bigger change to the image. Not
  worth it for phase 1–3; kept open (a later ADR can supersede this one when
  the core is stable and a need appears, e.g. audio in the core).
- **Keep patching Muuselabs' program**: see ADR-0002.

## Consequences
- Lua 5.1 limits (no integer type, no `goto`, `#` undefined with holes) are
  handled by the coding standard and tests.
- Size budget 176 KiB stripped (160 before ADR-0009); build step required (ADR-0006 keeps
  dependencies small).
- The loader's format (XOR + zlib) is reproduced by our build tool
  (`lua_patches.encode` already does it).
