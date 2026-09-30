# ADR-0007 — Close root execution over HTTP; bind MQTT to localhost; password on the WebSocket

Status: accepted, partly built (2026-09-26; state below as of 2.0.9, 2026-09-29)

## What is built (2.0.2 to 2.0.9)
- mosquitto: 1883 bound to `127.0.0.1`, anonymous for the daemons on the Jooki; the
  WebSocket 8000 needs a per-Jooki password, generated once in `/data/openjooki/ws_secret`
  (kept across updates, not `/mnt/config`) and served to the page at its own origin
  (`/oj-auth.json`). Home automation: an opt-in LAN listener with the same password.
- Parent code (4 digits) in front of the actions that change things; reset by holding
  both track buttons ten seconds on the Jooki.
- Maintenance SSH: off by default, opened for one hour from Settings; since 2.0.8 it takes
  a public key, kept in `/data/openjooki/authorized_keys` (updates rewrite `/home`), only
  while the access is open and behind the parent code.
- `S58_mosquitto.sh` no longer takes `/mnt/config/mosquitto.conf` (the card's FAT part,
  writable from any computer) over the broker's own settings (2.0.8).
- `run_rpc_cmd.sh` (Muuselabs' signed remote commands) neutralised.

## Still open
- **`/ll` and `/cmd/*` of `web_ctrl` still answer on the LAN** (the closed web server; no
  firewall on the device): fencing them needs a binary patch or a replacement of
  `web_ctrl`. Until then, the home Wi-Fi remains the trust boundary for those two.

## Context
`web_ctrl` (closed) answers `GET /ll?action=<shell>` as root and `/cmd/*`
(reboot, factory reset, format) to any device on the Wi-Fi, without
authentication. mosquitto listens on all interfaces on 1883 and 8000 with no
password. The OpenJooki phone installer relies on `/ll` to bootstrap a
factory Jooki. 1.x documents this as a known limit.

## Decision
- The phone installer keeps using `/ll` **once**, on a factory Jooki, to
  install OpenJooki; the OpenJooki image then **disables `/ll` and `/cmd/*`**
  for the LAN (reverse proxy rule in front of `web_ctrl`, or `web_ctrl`
  replaced by our own static server if the proxy is not possible — to be
  settled in phase 4 with a spike).
- Updates and privileged actions become bus commands gated by a one-time code
  shown on the Jooki's page (or a physical button press within 30 s).
- mosquitto: 1883 bound to `127.0.0.1`; WebSocket 8000 keeps serving the page
  with a per-Jooki password (generated at first boot, shown in Settings,
  changeable, stored in `/mnt/config`).
- No outbound connections except NTP and, on user request, GitHub.

## Alternatives
- **Leave as is** (trust the home LAN): most homes are trustworthy, but guest
  devices, IoT gadgets and children's tablets are not, and a root shell is a
  large surface for a toy.
- **TLS everywhere**: certificates on a device without a clock at boot and
  without a domain add more failure modes than they remove; localhost binding
  plus a password is the right size.

## Consequences
- Community tools that used 1883 from the LAN need the WebSocket password
  (documented; a `--legacy-open-mqtt` setting keeps the old behaviour for
  those who want it, off by default).
- Phase 4 needs a spike on how to fence `web_ctrl` (proxy vs replacement).
