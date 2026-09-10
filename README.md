# OpenJooki

Bring your **Jooki v2** back to life after Muuselabs shut down its servers — and
keep it yours. Safe backups, security fixes, and updates that **cannot brick your
Jooki**.

> Independent community project, not affiliated with Muuselabs / Jooki.

---

## Just want to update your Jooki?

You only need a computer on the **same Wi‑Fi** as the Jooki, and Python 3
(already on macOS and Linux; on Windows install it from python.org).

1. Download this project (green **Code** button → **Download ZIP**, then unzip).
2. Open a terminal in the folder and run:
   ```sh
   python3 tools/openjooki/installer_web.py
   ```
3. Your browser opens. **Drag your firmware file onto the page**, click
   **Install safely**, and wait. That's it.

A progress bar does everything: it writes to the spare copy of the system,
checks it **bit‑for‑bit**, switches over, and tests it. **If anything is wrong,
the Jooki goes back to the version it had before, on its own.** You cannot brick
it.

> On a phone? Run `python3 tools/openjooki/installer_web.py --lan` and open the
> address it prints, from your phone on the same Wi‑Fi.

---

## Why it's safe

Every change goes through the Jooki's own A/B update system:

- it writes to the **spare** partition, never the one currently running;
- the transfer is **verified bit‑for‑bit** (sha256);
- switching over **arms an automatic rollback** — if the new version doesn't
  start, the Jooki returns to the previous one at the next power‑up.

The bootloader and the factory partition are **never** touched.

---

## Want to go further?

Everything is open and readable. Start here:

- **The tool** — `tools/openjooki/` : a small Python CLI (`jooki.py`) to discover,
  back up, re‑add music, and apply firmware patches over your local network.
  See [tools/openjooki/README.md](tools/openjooki/README.md).
- **Updates from GitHub** — how a Jooki can fetch a release from this repo and
  install it by itself: [docs/15-ota-github.md](docs/15-ota-github.md).
- **Full technical write‑up** — how the Jooki works and how it was taken apart:
  - [docs/04-architecture.md](docs/04-architecture.md) — hardware & data model
  - [docs/06-root-access.md](docs/06-root-access.md) — getting root over SSH
  - [docs/08-system-mqtt-map.md](docs/08-system-mqtt-map.md) — the internal MQTT bus
  - [docs/09-internals-deep-dive.md](docs/09-internals-deep-dive.md) — firmware internals
  - [docs/10-patch-tool-design.md](docs/10-patch-tool-design.md) — the anti‑brick A/B patch design
  - [docs/12-firmware-audit.md](docs/12-firmware-audit.md) — security audit & fixes
  - [docs/14-cross-platform-installer.md](docs/14-cross-platform-installer.md) — Mac/PC/phone installer
  - …and the rest of `docs/` (community survey, maintenance plan, content API, roadmap).

---

## Layout

```
tools/openjooki/          the tool, the web installer, the auditable fixes
tools/openjooki/device/   scripts that run on the Jooki (self-install, OTA)
docs/                     technical analysis, architecture, runbooks, audit
scripts/                  utilities (prepare a release)
```

## Contact

Guillain d'Erceville — guillain@poulpe.us

## License

MIT. Use at your own risk; the tool is designed to be safe, but always keep a
backup.
