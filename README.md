# OpenJooki

Bring your **Jooki v2** back to life after Muuselabs shut down its servers — and
keep it yours. Safe backups, security fixes, and updates that **cannot brick your
Jooki**.

> Independent community project, not affiliated with Muuselabs / Jooki.

---

## Install / update from your phone — no computer

Your **Jooki v2** installs OpenJooki **by itself**, straight from this project.
From a phone (or any device) on the **same Wi‑Fi** as the Jooki:

1. Open the installer page: **https://guillain-rdcde.github.io/OpenJooki/**
2. Type your Jooki's **IP address** (find it in your router's device list, or
   the Jooki app). The page remembers it for next time.
3. Tap **Install OpenJooki** (first time) or **Update** (already on OpenJooki).
   A short confirmation explains what will happen — confirm, then **just wait**.

The page then shows a **spinner and a countdown** while the Jooki downloads
OpenJooki, installs it, and **restarts on its own** — about **10–15 minutes** for
a first install, **~2 minutes** for an update. Nothing else appears on screen,
and that's normal. Your **music and Wi‑Fi are kept**. Keep it plugged in.

> A tiny throwaway `ok` tab may flash up when the command is sent. It's harmless,
> and the page closes it for you where the browser allows. Because the page is
> served over HTTPS and the Jooki answers over plain HTTP, the browser won't let
> the command fire completely invisibly — but the Jooki receives it either way,
> so closing or ignoring that tab changes nothing.

**It cannot brick your Jooki**, and only a Jooki **v2** is accepted (a v1 is
refused before anything is written). See *Why it's safe* below.

### Prefer a computer?

On a machine on the **same Wi‑Fi**, with Python 3 (already on macOS/Linux; on
Windows install it from python.org):

1. Download this project (green **Code** button → **Download ZIP**, then unzip).
2. In a terminal in the folder, run:
   ```sh
   python3 tools/openjooki/installer_web.py
   ```
3. Your browser opens. **Drag the firmware onto the page**, click **Install
   safely**, and wait. The same safe A/B install, with a progress bar.

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
- **Phone-first install & the installer page** — how the page talks to the Jooki,
  the browser constraints, the waiting UX, and going back to factory:
  [docs/16-phone-install.md](docs/16-phone-install.md).
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
