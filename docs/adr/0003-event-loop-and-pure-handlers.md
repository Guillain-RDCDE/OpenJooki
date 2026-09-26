# ADR-0003 — One event loop, pure handlers, ports and adapters

Status: proposed (2026-09-26)

## Context
The old program is single-threaded already, but handlers read the clock, run
shell commands, write files and publish messages from anywhere, which makes
them untestable in isolation and their side effects unpredictable.

## Decision
- The kernel owns the only loop: it reads the bus socket, the mDNS socket and
  the timers, and delivers **events** one at a time.
- A handler is a pure function `(state, event) → (state', commands)`; it
  never performs I/O. The kernel executes the returned commands through
  **adapters** (bus, files, clock, host, shell, mdns), each with a fake for
  tests.
- Errors in a handler are caught, logged, counted; the loop never stops.

## Alternatives
- **Callbacks with direct side effects (as today)**: simpler to write at
  first, impossible to test without the whole system, hidden ordering bugs.
- **Coroutines per subsystem**: more expressive, but harder to reason about on
  a 27 MB device and unnecessary for this event rate (< 10 events/s).

## Consequences
- Some code becomes more verbose (a handler returns a command instead of
  calling `publish`). Accepted: it is the price of testability.
- The state is one document; modules own sub-trees; the kernel bumps the
  revision and publishes diffs.
- A lint rule forbids `require` of adapters from `services/`.
