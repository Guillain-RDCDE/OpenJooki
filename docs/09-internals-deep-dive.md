# Jooki v2 — fine-grained decompiled analysis (ESP32 + all internals)

_Static analysis of the original firmware (root SSH, without opening the device).
Original sources: `ml-jooki-controllers` (Muuselabs), C + Lua, git 3f3ed7dca7._

## 1. ESP32 — protocol fully decoded (without decrypting the firmware)
The Ingenic SoC talks to the ESP32 through an **htdrv** kernel driver:
- `/dev/esps0`: **command/response** channel (protobuf, serialized)
- `/dev/espnotif0`: **asynchronous notification** channel (events)
- `/sys/kernel/htdrv/fw_version`: ESP32 firmware version
- `/sys/kernel/htdrv/mac`: WiFi MAC address
Protocol = **ESP-Hosted** (Espressif) over **protobuf** (`esp_hosted_config`,
`esp_hosted_notif`). The ESP32 provides **WiFi + Bluetooth + NFC + buttons/knobs
+ power info** to Linux (network interface `ethsta0`).

### ESP32 firmware (file on disk — we have access to it)
`/etc/esp32/factory_default_firmware.tgz` (reflashed if the
`/data/mode/ESP32_FIRMWARE_LOADED` flag is absent, cf. `bin/ota2.sh`).

### Commands (Cmd → Resp) — ~40, complete catalog
- **NFC**: GetNfcMode, SetNfcMode, WriteTag, (get current tag)
- **WiFi**: AddAP, RemoveAP, GetAPScanList, GetConfiguredAPList, GetAPConfig,
  SetAPConfig, Get/SetWiFiMode, DisconnectAP, SetProvisioning, SetGotIP,
  Get/SetMacAddress, GetAirplaneMode
- **Bluetooth**: StartBluetoothScan, ConnectToBluetoothDevice,
  ForgetBluetoothDevice, GetAllBluetoothStates, SetBluetoothAutoconnectEnabled,
  Get/SetBtmSecFlags
- **Device**: GetDeviceInfo, GetStarInfo, GetKnobsState, GetRtcInfo,
  Get/SetPowerSaveMode, Get/SetToysafe, SetVersions, SetLogLevel, Reset,
  SendAllNotifications, SetRemoteCommandExecutionResult
- **Reset actions**: Reset_All, Reset_Bt_Devices, Reset_Calibration,
  Reset_Wifi_Credentials
- **WiFi encryption modes**: Open, WEP, WPA_PSK, WPA2_PSK, WPA3_PSK,
  WPA2_WPA3_PSK, WPA2_ENTERPRISE…

### Notifications (events pushed by the ESP32)
- **TypeNotifNFC** → format: `tag='<UID hex>' star=0x<XX>` (token placed);
  published to MQTT on `/j/nfc/input/tag`; removal → `/j/nfc/input/tag_removed`
- **TypeNotifKnob** → `id=<n> value=<v>` (buttons/knob)
- **TypeNotifWifi** → events (eConnect, eGotIP, eDisconnected…) / states
- **TypeNotifBluetoothState / Device**
- **TypeNotifRemoteCommandExecution**

### `esp32_cmd` CLI (useful verbs)
`nfc_get_mode`, `nfc_set_mode`, `nfc_get_current_tag`, `nfc_write_tag`,
`wifi_add_access_point`, `wifi_remove_access_point`, `wifi_ap_scan_list`,
`wifi_get_configured_access_points_list`, `wifi_disconnect_ap`,
`wifi_set_provisioning`, `wifi_get_mac`, `wifi_set_mac`, `nvs_reset`,
`bluetooth_start_scan`, `bluetooth_set_autoconnect_enabled`, `set_toysafe`,
`set_versions`, `set_remote_command_execution_result`.
→ **We can read the current token and write new NFC tags** from the command
line, without external hardware.

## 2. Web interface (`web_ctrl`, Mongoose server)
Complete route table:
- `/` `/ui/` `/setup` `/favicon.ico` — the SPA + WiFi config pages
- `/upload` — file upload (→ /tmp/web_ctrl_dirs/uploads/)
- `/config` (read) / `/set_config` (write `/mnt/config/jooki.conf`)
- `/ll` `/flags` — execution (backdoor) / flags
- `/rpc` + `/run/rpc_cmd`(+`.sig`) — signed command (openssl, run_rpc_cmd.sh)
- `/cmd/{reboot,poweroff,factory_reset,reset_wifi,sdcard_format,mender_start,
  mender_commit,dtb,dtb_vp1}` — device control
- `/api/wifi/v1/{add,restart}` — WiFi onboarding
- `/ping` — local heartbeat
Serves the SPA from `/jooki/app/www/public`.

## 3. Audio player (`player`)
- **Lua 5.1.5** (logic in `player.lib`, bytecode) + **ALSA** (libasound, ALSA
  mixer for volume) + miniz (zip). Driven via `/j/audio/out/*`, state via
  `/j/audio/input/*`. (GStreamer present for Spotify.)

## 4. LED (`ht_ctrl`)
- LED chip on **I²C** (`/dev/i2c`, "HT" device, with EEPROM), notion of **LED
  groups** + animations. Commands `/j/led/output/{set,set_raw,pulse,
  pulse_raw,charge_state}`.

## 5. Buttons (`gpio_ctrl`) & power
- Buttons → `/j/gpio/input/{next,prev,fwd,rew,vol_inc,vol_dec,vol_set,circle,
  hp_plugged,airplane_*}`. Battery/charge → `/j/power/input/*`.

## 6. Startup & boot
- `ml-start-app.sh` launches in a loop: gpio_ctrl, ht_ctrl, esp32_ctrl, player,
  web_ctrl (+ spotify_ctrl). Bus = **mosquitto** (MQTT 1883).
- **Device tree**: `/boot/ml-j1000.dtb` (+ `ml-j1000-vp1.dtb`), selected via the
  U-Boot env (`set_uboot_env.sh dtb ...`). Useful for rebuilding the kernel.
- OTA: mender, A/B, from my.jooki.rocks (dead).

## 7. Actual data model (with real UIDs)
`tokens.json`: UID (7 bytes, prefix 04) → { name, starId, seen }. Real examples:
`0433366AE74C81`→Whale/Jooki.Whale, `044A506AE74C81`→Dragon/Jooki.Dragon,
`04E116924B7080`→Blue token/G2.DarkBlue, `0494109A4B7080`→Orange token/G2.Orange…
`playlists.json`: { tagId(=UID), title, audiobook, tracks:[uploadId…] }.
`tracks.json`: uploadId → metadata; files in `uploads/<uploadId>`.
`audiocfg.json`: volume, shuffle, repeat, headphones.

## 8. What's left to recover to own it all
- The ESP32 firmware `/etc/esp32/factory_default_firmware.tgz`.
- Kernel + `/boot/ml-j1000*.dtb` + config + U-Boot env + `htdrv` kernel module.
- (Optional) decompile `player.lib` (Lua) if we want the exact playback logic.
Everything is reachable over SSH root, without opening the device.

## 9. RECOVERED AND CONFIRMED (09/2026) — we own the ESP32 and the boot
Extracted from the Jooki over SSH (in `backups/firmware-*/`):
- **Complete, reflashable ESP32 firmware** (`/etc/esp32/factory_default_firmware.tgz`):
  `esp32/jooki_v2.bin` (Muuselabs ESP-Hosted app), `bootloader/bootloader.bin`,
  `partition_table/partition-table.bin`, `ota_data_initial.bin`,
  `flasher_args.json` (esptool offsets) + `flash.sh`, `VERSION.txt`.
  → We can reflash the ESP32, and eventually put our own firmware on it.
- **ESP32 transport**: kernel drivers `esp32sdio.ko` (high-throughput **SDIO**
  link for WiFi/BT) + `ml-j2000-htdrv.ko` (control/notif → `/dev/esps0`,
  `/dev/espnotif0`, `/sys/kernel/htdrv/*`).
- **Kernel**: `/boot/uImage-5.7.0` (U-Boot uImage, DTB embedded — `mender_dtb_name=none`).
- **Boot (U-Boot env)** — the keys for v3:
  - `bootargs=console=ttyS2,115200n8 mem=32M@0x0 ... root=<A/B> rootfstype=ext4 rw`
  - **RAM = 32 MB only** → keep the v3 app lightweight (MPD + small server, OK).
  - Mender A/B boot: `ext4load` of `/boot/uImage` from mmcblk0p2 or p3, `bootm`.
  - Debug console: **ttyS2 @115200** (if a USB-serial adapter is added someday).
- Original firmware version: `n20221206-5ce8778-70b40631` (Dec. 2022).

### State of ownership
We now hold, backed up off-device: the **data** (playlists, tokens, MP3s), the
**system/app**, the **ESP32 firmware** (+ flasher), the **kernel** and its
**drivers**, the **U-Boot env**, and the **complete understanding** (MQTT bus,
ESP32 protocol, web API, data model). All that's missing, for a full hardware
clone, is the raw disk image (dd) — optional, since the device boots from a
removable SD.
