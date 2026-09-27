# Jooki v1 (J1000): recovery through the serial console (UART)

Goal: get back into a **Jooki v1** whose Wi-Fi refuses every network (the setup
portal fails at once and the device goes back to "setup" mode). The usual ways in
are closed: Wi-Fi fails, USB shows nothing on the computer side, and there is **no
removable SD card** (the memory is soldered). The serial console (UART) gives a
**shell on the internal Linux** without Wi-Fi: it is the way back in.

> Hardware reminder, from the analysis of the v2 firmware (same family: the v2 still
> ships `ml-j1000.dtb`): **Ingenic** SoC (X1000 family, MIPS), U-Boot + Linux 5.7.0,
> BusyBox userspace, an **ESP32** co-processor for Wi-Fi, Bluetooth and NFC. Kernel
> console: **`ttyS2`, 115200 8N1** (`console=ttyS2,115200n8` in the boot arguments).
> To be confirmed on the v1 at the first boot.

---

## 1. Safety (read before plugging anything)

- The Jooki's UART uses **3.3 V logic**. Use a USB-TTL adapter set to **3.3 V**
  (not 5 V), or the board can be destroyed.
- **Never connect the adapter's VCC/3V3 wire** to the board: the board has its own
  supply (battery/USB). Only **GND, TX and RX** are connected.
- Always connect **ground first** (GND to GND).
- Wire with the Jooki off, power it on afterwards.

## 2. Hardware

- A **3.3 V** USB-TTL adapter (CP2102, CH340 or FT232, set to 3.3 V).
- 3 female Dupont wires (or wires to solder if the pads are bare).
- Optional: soldering iron and multimeter.

## 3. Finding the UART pins on the board

Look, usually near the SoC or the shield, for:

- a small **group of 3-4 pads or holes** in a row (often `GND TX RX VCC`),
- sometimes printed `RX`/`TX`/`GND`, sometimes bare (test points).

With a multimeter (board off, then on):

- **GND**: continuity with the metal shield / the negative pole.
- **TX (board side)**: about **3.3 V** at rest, and it "moves" (short drops) at
  boot while the boot log comes out.
- **RX (board side)**: about 0 V or floating at rest.
- **VCC**: a steady 3.3 V all the time: **do not use it**.

> If unsure between two pads for TX and RX, getting it wrong is harmless at 3.3 V:
> swap the two wires and try again. A clear photo of the area helps identify them.

## 4. Wiring

| USB-TTL adapter | Jooki board |
|---|---|
| GND | GND |
| RX  | TX (board) |
| TX  | RX (board) |
| VCC/3V3 | **DO NOT CONNECT** |

(The adapter's RX listens to the board's TX and the other way round: crossed.)

## 5. Opening a serial terminal (macOS)

Plug the adapter in, then find its port:

```sh
ls /dev/cu.usb*      # e.g. /dev/cu.usbserial-XXXX or /dev/cu.usbmodemXXXX
```

Open the console at 115200 baud:

```sh
screen /dev/cu.usbserial-XXXX 115200
# (quit screen: Ctrl-A, then K, then y)
```

If nothing readable shows at boot: swap TX and RX, then try other speeds
(`57600`, `230400`, `9600`).

The console can also be driven remotely: once the adapter is plugged into a
computer reachable over SSH, the same `screen` session can be opened from there.

## 6. First boot: what to capture

Power the Jooki on with the console open. The U-Boot log should appear, then the
kernel's. The aim is to confirm **SoC, speed, root partition and whether there is a
shell**. Worth noting or copying:

- lines with `U-Boot ...`, `Ingenic`, `mmcblk0`, `mender_boot_part`,
- the end of the boot: either a **root prompt** (`# `) straight away, or a login prompt.

## 7. Getting a root shell

Depending on the firmware, two cases:

- **Direct root console**: the boot leaves a `# ` prompt: you are root.
- **Otherwise, through U-Boot**: during the very first seconds, press a key
  repeatedly to **stop U-Boot** (a prompt such as `=>` or `jooki=>`), then boot in
  single-user mode by adding `init=/bin/sh` to the boot arguments. Generic example
  (to adapt to the real log):

  ```
  => setenv extra_bootargs init=/bin/sh
  => run bootcmd
  ```

  The exact variable name depends on the U-Boot environment shown in the log.

## 8. Once root: ALWAYS back up first

Before any change (OpenJooki rule: never write without a backup):

```sh
# inventory
cat /proc/cmdline; uname -a; cat /etc/*version* 2>/dev/null
cat /proc/partitions; mount

# backups (adapt the paths to the real log)
# - configuration, data, content:
tar czf /tmp/backup-config.tgz /mnt/config 2>/dev/null
tar czf /tmp/backup-data.tgz   /data 2>/dev/null
# - ESP32 firmware + kernel + environment (as on the v2):
ls -l /etc/esp32/ /boot/ 2>/dev/null
```

Bring these archives back over the console (or, better, as soon as the network
works again) and keep them next to the v2 backups.

## 9. Diagnosing and fixing the Wi-Fi (the heart of the problem)

Wi-Fi and NFC go through the **ESP32** co-processor (drivers `esp32sdio.ko` and
`ml-j2000-htdrv.ko` on the v2; the v1 equivalent is to be confirmed). Once root:

```sh
dmesg | grep -iE "esp|wifi|htdrv|sdio"      # state of the ESP32 link
ls /sys/kernel/htdrv/ 2>/dev/null            # fw_version, mac...
# ESP32 command line (if present):
esp32_cmd wifi_get_mac
esp32_cmd wifi_ap_scan_list                  # does the ESP32 see the networks?
```

Depending on what shows:

- **Corrupted ESP32 Wi-Fi settings (NVS)** (first hypothesis): reset the ESP32
  configuration with `esp32_cmd nvs_reset` (or `Reset_Wifi_Credentials`), then set
  it up again.
- **Add the network directly** (bypasses the broken portal):
  `esp32_cmd wifi_add_access_point "<SSID>" "<key>"`, then check
  `wifi_get_configured_access_points_list` and that an IP address is obtained.
- **ESP32 to be re-flashed**: apply `factory_default_firmware.tgz` again
  (`flash.sh`/esptool); the ESP32 keeps a factory partition and an OTA one as a
  safety net.

At the same time, apply what was learned on the v2 so that the fix holds:

- **Neutralise the dead cloud** (prevents reboots and reverts caused by
  `my.jooki.rocks`): the `cut-cloud` patch.
- **Lasting root access**: SSH key + dropbear at boot (as in docs/06), so that the
  rest can be done **over the network**, without the console.

## 10. Then: the same work as on the v2

Once the device is root and the network works, the OpenJooki v2 pipeline applies:
full backup, audit and hardening, fixes through the Mender A/B partitions (no brick),
and, if useful, a v1 image.

---

### Checklist for the day

1. Jooki open, 3.3 V USB-TTL adapter wired to GND/TX/RX.
2. A **photo of the pad area** if TX and RX are uncertain.
3. The console open (locally or over SSH), then steps 6 to 10.

*(No personal data (network name, password, MAC address) is included here on
purpose, since this document belongs to the public OpenJooki repository.)*
