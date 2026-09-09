# Jooki v2 firmware audit (existing) — report

_Professional static audit of the 51 shell scripts in the firmware (busybox/ash, MIPS).
The binaries (player, web_ctrl, esp32_ctrl…) are compiled and out of scope.
Principle: reconcile every finding with the fact that **this firmware ships and
runs** — so the constructs used throughout (`${var:i:len}`, `nice -N`) are
supported by this busybox; "bugs" that would break the nominal path are
discarded as false positives._

## Discarded false positives (the device runs, so these paths work)
- `nice -5/-6` in `ml-launch-controller.sh`: this busybox accepts it (the daemons
  start). Not portable, but not a bug here.
- `${text:$i:1}` (speak_info.sh) and other substrings: supported (ble.sh, etc. use
  them and work). Non-POSIX but fine on this build.

## CRITICAL — root code-execution backdoors
1. **heartbeat.sh — RCE via `## ML_OTA`** (SSL `verify=0` + execution of the server
   response). ✅ **ALREADY NEUTRALIZED by our `cut-cloud` patch.**
2. **ble.sh `custom()` (cmd `_`) — RCE backdoor over Bluetooth.** ✅ **APPLIED (v0.1.1, `patch harden`)** — `u)` and `_)` neutralized, legitimate cases kept.
 Executes arbitrary `$cmd`
   as root; the "protection" is `md5(cmd)[5:8]`, derived from the command
   itself = not a secret. Anyone within BLE range can exploit it.
   → Fix: remove `custom`/`userset` (debug commands), or require a real
   provisioned HMAC secret + allow-list.
3. **run_rpc_cmd.sh — verify-then-execute TOCTOU.** ✅ **APPLIED (v0.1.1)** — now refuses remote execution.
 `openssl … -verify $filename`
   then `/bin/ash $filename` **re-reads** the file: swappable between the two.
   Unquoted variables on top.
   → Fix: copy into a root-only tmpfs, verify THAT copy, execute the
   same one; quote.
4. **wifi_setup/wifi_add.sh — awk injection via `indx`.** `awk "NR==$indx"` with
   `indx` coming from the captive-portal form, unvalidated → `system()` = RCE (AP/
   onboarding mode).
   → Fix: validate integer (`case "$indx" in *[!0-9]*) exit 1`), `awk -v n="$indx"`.

## HIGH — integrity / injection
5. **ota2.sh — firmware validated by MD5 only + URL/MD5 as arguments.** No
   cryptographic authenticity. (OTA is dead anyway.)
   → Fix: cleanly disable OTA, or embed public-key signing.
6. **wifi_add_network.sh — injection into wpa_supplicant.conf.** SSID/pass inserted
   raw via `echo -e` (interprets `\n`) → directive injection; `ssid_hex` not
   validated → path traversal.
   → Fix: reject `"`/newlines/backslash, `printf '%s'`, validate `ssid_hex`.
7. **wifi_setup/generate_html.sh — stored XSS via SSID name** (broken HTML
   escaping) in the captive portal.
   → Fix: real HTML entity encoding.

## MEDIUM — dead cloud, robustness, functional
8. **check_online.sh — infinite loop after shutdown.** ✅ **APPLIED (v0.1.1)** — launches the heartbeat (no-op) without the dead ping.
 `heartbeat.sh S_LIVE` is
   launched **only after** a successful ping to `my.jooki.rocks` (dead) → eternal
   `sleep 10` loop, the S_LIVE state is never emitted, permanent network/CPU waste.
   `curl -k` (TLS disabled) on top.
   → Fix: launch the heartbeat (now a no-op) without depending on the dead ping;
   remove the cloud check.
9. **suspend.sh — broken shutdown.** On timeout: `./poweroff.sh # this is gone`
   → nonexistent script, `set -e` exits without powering off → **battery drain**.
   → Fix: `/sbin/poweroff`.
10. **power_overheat.sh — infinite loop** without re-reading the temperature or
    exiting: stays in alert/pause even after cooling down.
11. **wait_for_file.sh — infinite wait** with no timeout (inconsistent with
    wait_for_mosquitto, which caps it). ✅ **APPLIED (v0.1.1)** — default timeout 120 s.
12. **is_mounted.sh — unanchored/unquoted `grep $1`** → false mount positive
    (risk for downstream rsync/rm, e.g. init_sdcard). ✅ **APPLIED (v0.1.1)** — anchored `grep -qF " $1 "`.
13. **init_sdcard.sh — `mv $TMP $DST` nests** if `$DST` partially exists →
    broken content structure.
14. **ml-launch-controller.sh — 1 Hz restart with no backoff**: if a daemon fails in
    a loop, restart storm + syslog flood.

## LOW
- `set -eu` missing in several launchers/loggers; unquoted variables (edge-case
  impact); fractional `sleep 0.2` (variable busybox support); predictable temp
  files not cleaned up (record.sh); double sysfs write (ml-start-app-audio.sh:49).

## Application status (v0.1.1)

**Applied and 100% verified on the device** (A/B flow, rollback preserved):
- #1 heartbeat RCE `## ML_OTA` — via `patch cut-cloud`.
- #2 `ble.sh` backdoors `u)`/`_)`, #3 `run_rpc_cmd.sh` TOCTOU, #8 `check_online.sh`
  dead loop, #11 `wait_for_file.sh` timeout, #12 `is_mounted.sh` anchored — via
  `patch harden` (auditable files in `tools/openjooki/patches/`).

**Deferred (reason documented)**:
- #9 `suspend.sh` (battery): clear fix (`/sbin/poweroff`) but **unverifiable
  without powering off the device** / serial console — to be done when a test bench
  is available.
- #5 `ota2.sh` / OTA: the Mender machinery **underpins our own A/B tool**;
  touching it puts the anti-brick guarantee at stake. To be handled separately,
  carefully.
- #4/#6/#7 (Wi-Fi onboarding / captive portal): AP paths rarely exposed;
  fixes ready, to be applied in a dedicated "onboarding" batch.
- #10 `power_overheat.sh`, #13 `init_sdcard.sh`, #14 launcher backoff: robustness,
  later batch.

## What we fix in OpenJooki v0.1.x (safe, high-value subset)
All applicable via the **proven A/B patch flow** (clone → patch → switch → rollback):
- **Security (priority)**: RCE backdoors neutralized — heartbeat ✅, `ble.sh`
  custom/userset ✅, `run_rpc_cmd` TOCTOU ✅; dead OTA: disabling deferred.
- **Dead cloud**: `check_online.sh` fixed ✅ (heartbeat launched without the dead ping).
- **Battery / UX**: fix `suspend.sh` (real shutdown) — concrete gain.
- **Robustness**: `wait_for_file` timeout ✅, `is_mounted` anchored ✅; `power_overheat` deferred.
Each fix: small, targeted, tested, reversible.
