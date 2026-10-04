# Connect a Jooki to Wi-Fi without the app

> **Parents**: use [the Wi-Fi page](https://guillain-rdcde.github.io/OpenJooki/wifi.html).
> This file is for those who want the terminal tool or the details.

A Jooki 2 only learnt its Wi-Fi network from the old app, at the first start. Move
house, change the box or its password, and its side dots stay orange: no Wi-Fi, no page. Its Wi-Fi chip
also speaks Bluetooth, though, and always offers the same set-up the app used:
Espressif's provisioning (protocol v1.1, no security, `wifi_scan`), plus Muuselabs'
own list of remembered networks. Two things speak it:

- **[The page](https://guillain-rdcde.github.io/OpenJooki/wifi.html)**, in Chrome or
  Edge on Android, Windows, Mac or Linux (Web Bluetooth). Nothing to install: find the
  Jooki, pick a network, type the password.
  **Not on iPhone or iPad**: iOS exposes Web Bluetooth to no browser (all of them run on
  WebKit, Chrome included). The only ways round are a native App Store app (not planned:
  no personal Apple developer account) or third-party "Web Bluetooth browsers", refused
  because the audience is parents with no technical skill. The page says so plainly.
- **`jooki_wifi.py`**, the same from a terminal, on Windows, Mac and Linux:

```sh
pip install bleak
python3 jooki_wifi.py                    # guided: pick a network, type the password
python3 jooki_wifi.py scan               # the networks the Jooki can see, and the ones it remembers
python3 jooki_wifi.py connect "My box"   # asks for the password (hidden)
python3 jooki_wifi.py status             # what it is on
python3 jooki_wifi.py list               # the networks it remembers (the Jooki stays on its Wi-Fi)
python3 jooki_wifi.py forget "Old box"   # make it forget one (the Jooki stays on its Wi-Fi)
```

`scan`, `status` and the guided mode **take the Jooki off its Wi-Fi** until it is given a
network (`connect`), or until it restarts: on the charger it does so by itself after ten
minutes (OpenJooki 2.0.8 or later). `list` and `forget` do not.

Bluetooth must be on. Several Jookis around: `--name JOOKI2_XXXXXX` (the name is
`JOOKI2_` + the end of the Jooki's serial, shown on its page under *Settings → Wi-Fi → Change network*).

## What was found on a real Jooki (28 September 2026)

- The Jooki advertises `JOOKI2_<id>` **all the time**, connected to Wi-Fi or not
  (service `b3562d79-1a6f-6c59-368a-599ca5481a90`). So the page also works to
  *move* a connected Jooki to another network, or to make it forget one.
- Endpoints (Espressif names, from the `0x2901` descriptors): `proto-ver` (ff53),
  `prov-session` (ff51), `prov-config` (ff52), `prov-scan` (ff50) in that service;
  `wcm-list-config-ap` (read: `"a","b"`), `wcm-remove-ap` (write: `"a"`) and
  `wcm-add-ap` in `5bf49f8c-3491-218c-ae4f-db0580debd00`; `firmware-versions` is
  the standard Firmware Revision string (JSON with the ESP, PMIC and Linux versions).
- **The handshake matters**: write `ESP` to `proto-ver` and read the answer *before*
  opening the security-0 session, and open a **new session before every set-up**
  (`set_config` + `apply_config`). Otherwise the Jooki answers application error
  `0x85`, or refuses the set-up after a previous attempt.
- The `ip4_addr` in the "connected" status is meaningless (Linux does DHCP, not the
  chip): the page never shows it.
- `get_status` reports the chip's *last provisioning event*, not its live state: a
  connected Jooki that was never provisioned over Bluetooth says "connecting". After
  `apply_config`, a wrong password ends either in `failed` / `AuthError` after ~10 s
  or in "connecting" forever; the page waits 45 s and says so. A failure is believed
  only when reported twice, at least 3 s in.
- **Opening the set-up session takes the chip off its Wi-Fi** until it is given a network
  (29/09: one `list` with a session left our Jooki offline for good; `apply_config` alone
  is refused, code 5). `wcm-list-config-ap` and `wcm-remove-ap` need no session, and the
  tools no longer open one for them. `wcm-remove-ap` is safe even for the network in use.
- The chip keeps the **last network it reconnected to by itself**, not the strongest, and
  a network given over Bluetooth does not change that: with two networks it can stay on
  the far one after a cut. Keep only the network next to the Jooki (docs/20).
- **A wrong password on the network in use drops the Jooki off Wi-Fi**, and the chip
  did not come back by itself within two minutes: the tools say so and the user
  tries again. Never test with the only network that works, unless you are next to it.
- Chrome's device chooser takes a few seconds to list the Jooki. In a test, the
  chooser is answered through CDP `DeviceAccess.selectPrompt`, which works with the
  real adapter (`scratch: real_page_test.py` of the 28/09 session; the bench uses a
  scripted `navigator.bluetooth`, see `tools/openjooki/tests/test_wifi_page.py`).
- `esp32_cmd start_provisioning` on the Jooki is marked deprecated and is not
  needed: nothing has to be done on the Jooki's side.
