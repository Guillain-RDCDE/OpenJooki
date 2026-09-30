# ADR-0007 — Close root execution over HTTP; bind MQTT to localhost; password on the WebSocket

Status: accepted, **fully built** (2026-09-26; `/ll` and `/cmd` closed 2026-09-30)

## What is built (2.0.2 to 2.1.0)
- **`/ll` and `/cmd/*` are gone (2.1.0).** `web_ctrl` (the closed server that answered a root shell
  and reboot/factory-reset/format to anyone on the Wi-Fi, without a password) is **no longer started**
  (`ml-start-app.sh`). The 2.0 core serves the page and the one `POST /upload` itself
  (`adapters.httpd`, port 80): it has no `/ll` and no `/cmd`, refuses a foreign `Host` (the
  rebinding guard web_ctrl had), and never runs a shell from a request. Maintenance SSH is opened
  from the page over the WebSocket (below), so closing web_ctrl does not remove the way in. The
  factory phone-installer still uses the factory image's own web_ctrl once to install OpenJooki.
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
- Nothing. The last item — `/ll` and `/cmd/*` — was closed in 2.1.0 by replacing web_ctrl with the
  core's own server (`adapters.httpd`) rather than a binary patch: our code, testable
  (`tools/openjooki/tests/test_httpd.py`), and it drops the two routes by simply not having them.

## Context
`web_ctrl` (closed) answers `GET /ll?action=<shell>` as root and `/cmd/*`
(reboot, factory reset, format) to any device on the Wi-Fi, without
authentication. mosquitto listens on all interfaces on 1883 and 8000 with no
password. The OpenJooki phone installer relies on `/ll` to bootstrap a
factory Jooki. 1.x documents this as a known limit.

## Decision
- The phone installer keeps using `/ll` **once**, on a factory Jooki, to
  install OpenJooki; the OpenJooki image then **disables `/ll` and `/cmd/*`**
  for the LAN. Settled in 2.1.0: **web_ctrl is replaced by our own server**
  (`adapters.httpd` in the core), not proxied and not binary-patched — there is
  no firewall on the device (no iptables/nftables), and our own server is the
  cleanest way to simply not offer those routes.
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
- Community tools that used `/ll` or `/cmd` no longer work; that is the point.
  Our server offers only the page and `/upload`.
- The core now holds an open TCP port (80). It is non-blocking, bounded (request
  head, upload size, connection count and idle timeout all capped), streams
  uploads to disk and files from disk, and never runs a shell from a request.
