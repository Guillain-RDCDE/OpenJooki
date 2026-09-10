# Phone-first install & the installer page

The front door is a single static page — `docs/index.html`, served at
`https://guillain-rdcde.github.io/OpenJooki/`. It lets anyone move a **factory
Jooki v2** to OpenJooki, or update one, from a phone on the same Wi-Fi, with no
computer. Proven end-to-end on a real device: factory Muuselabs → tap → download
→ sha256 verify → A/B write → self-reboot → OpenJooki running, music intact.

## How the page talks to the Jooki
The Jooki's built-in web control (`web_ctrl`, port 80) exposes `/ll?action=<cmd>`,
which runs a short root shell command and always replies just `ok` (no stdout,
~90-char limit). The page sends **one** command:
- **Update**: `curl … /o.sh; sh /tmp/o &`
- **Install**: `curl … /b.sh; sh /tmp/b &`

Everything else (download, verify, flash, reboot) happens on the device, detached
— it survives the browser tab closing.

## The hard browser constraint (why there's an "ok" tab)
The page is HTTPS (GitHub Pages); the Jooki answers over plain HTTP. Browsers
**block every silent cross-scheme request** (fetch/XHR/iframe/img are all
mixed-content) — the *only* thing allowed is a **top-level navigation** to
`http://<ip>/ll?…`, i.e. opening a tab. So the command cannot be fired invisibly;
a throwaway `ok` tab is unavoidable. The page opens it, then **auto-closes it**
where the browser permits (timer + focus/visibility handlers). On iOS that
auto-close isn't always allowed, so the tab may linger — it is explicitly marked
harmless, and since the Jooki already received the command, closing or ignoring
it changes nothing. For the same reason the page **cannot read the device's
status back**, so it can't show real progress.

## UX: never let it feel dead
Because the install runs silently for ~10–15 min, the page:
1. shows a **confirmation** first, stating plainly that *nothing will appear on
   screen for ~10–15 min, that's normal, the Jooki restarts itself, don't unplug*;
2. then switches to a full-screen **spinner + countdown** (time-based estimate,
   not real device progress) ending on a ✅ "should be back now";
3. accepts the IP with **commas or dots** (iOS numeric keypad has no dot),
   prefills from `?ip=` or `localStorage`, and remembers it.

## Going back to factory to test the full install
The original Muuselabs firmware is still on the device (factory partition p1, and
the un-overwritten A/B slot). To re-live the factory→OpenJooki path: switch the
boot slot to the Muuselabs one (`fw_setenv mender_boot_part …`; reversible) and
reboot — see `docs/04-architecture.md`. `/data` (music) is preserved throughout.

## Wi-Fi note
Wi-Fi is handled by the ESP32 co-processor (interface `ethsta0`), with networks
stored in the ESP32's own NVS — independent of the rootfs, so it survives an A/B
switch or a factory-slot swap. `/jooki/bin/esp32_cmd get_ap_status` shows the
connected SSID.
