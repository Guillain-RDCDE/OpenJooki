# What the community built around the Jooki (state as of 2026-09-09)

Summary: after Muuselabs shut down, the community mostly produced
(1) Home Assistant integrations, (2) a Wi-Fi re-provisioning tool,
(3) a local API library, (4) NFC token tools, and
(5) reverse-engineering articles. There is NO turnkey replacement app for
uploading music: the Jooki web interface (/upload) remains the main route,
but all the technical building blocks are documented.

Everything works LOCALLY (no cloud) through two channels:
- the embedded web interface: endpoints /upload, /config, /set_config, /ll
- an MQTT broker open on port 1883 (topics /j/web/input/*, /j/web/output/state)

## 1. Home Assistant integrations (local control via MQTT)
- **lpshanley/ha-jooki** — Python, the most complete and recent (updated March
  2026). Play/pause, next/previous track, seek, volume 0-100, browsing
  playlists AND figurines from the HA media card, virtual place/remove of a
  figurine + NFC event detection, battery, power, Wi-Fi diagnostics, Spotify
  status, "hearing-safe" filter, triggers on physical buttons. 100% local via
  the Jooki's MQTT broker, no cloud token.
- **ViViDboarder/ha-jooki** — Python, an older/simpler HA component (updated
  2026), same local MQTT principle. Less full-featured than lpshanley's.

## 2. Wi-Fi re-provisioning / reconnection
- **icelit-net/jooki-provision** — JavaScript, a Jooki "provisioner" in the
  browser via Bluetooth BLE (updated March 2026). Its exact purpose is to
  reconfigure / reconnect a Jooki to Wi-Fi without the dead app. By the
  author's own admission: "unrefined, unoptimised, LLM assisted" — useful but
  rough.

## 3. Local API library / client
- **rclancey/jooki** — Go, library + CLI (client.go, state.go, cmd.go). A
  low-level client to talk to the Jooki (state, commands). No web interface or
  ready-made upload; it's a building block for making a tool. README nearly
  empty. Lightly maintained (2021, minor activity in 2024).

## 4. NFC tokens
- **SveLil/JookiTagCreator** — TypeScript (StackBlitz), 4 stars, updated August
  2026. Generates the URLs to write onto NFC tags so they're recognized by the
  Jooki: you pick the token type + the tag's UID, and it produces the URL to
  write with an external NFC reader/writer. It does not talk to the Jooki
  directly; it's a tag-URL preparer.

## 5. Spotify utility
- **Gagi2k/jooki-random-spotify-episode** — Python (2025). Picks a random album
  from selected artists and stores it as a playlist. Depends on an active
  Spotify account (ours is linked but inactive).

## 6. Reverse-engineering articles (knowledge, not repos)
- **nv1t.github.io/blog/reviving-jooki** — THE reference: factory hotspot
  `mnet2` / password `muuselabs256`, web endpoints, adding an SSH key via
  /config then `ssh root@<ip>`, USB mode disabled from the factory
  (JOOKI_DISABLE_USB=1), partition layout, OTA mechanism.
- **there.oughta.be/an/interface-for-jooki** — describes the open MQTT broker
  (port 1883) and control via openHAB; topics DO_PLAY, set_raw (LED), etc.

## What this means for us
- To ADD MUSIC right now: the web interface (192.168.1.61 /
  jooki2-0426E8.local) → "Add a playlist" is enough, nothing to install.
- To AUTOMATE: a small homemade script that posts MP3s to /upload and
  creates/links the playlists is doable (the endpoints are known). This is the
  missing link nobody has packaged cleanly — a good candidate for a "Jooki"
  repo of our own.
- To INTEGRATE WITH HOME AUTOMATION: lpshanley/ha-jooki if we ever run Home
  Assistant.
- For NFC TOKENS: JookiTagCreator + an NFC reader to create new characters.
