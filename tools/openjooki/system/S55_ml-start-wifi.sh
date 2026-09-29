#!/bin/ash
# OpenJooki: the original Muuselabs Wi-Fi start script (kept as S55_ml-start-wifi.sh.openjooki-orig),
# with three changes for a safer start:
#  - the Muuselabs factory network ("mnet2", a network no home has) is no longer added to the Wi-Fi
#    chip at every start; it is removed when the chip also remembers a real network, so the chip
#    does not spend its tries on it;
#  - the chip gets 30 s to answer instead of 10 (a slow start is not a broken chip);
#  - a slow or failed chip no longer writes the "factory mode" flag, which stayed for good.
#    It is logged instead; the core retries the chip's set-up by itself.

ESP32_MMC_DEV=mmc1

ESP32_MODULE_NAME=esp32sdio
ESP32_MODULE_SLEEP_TIME=300

ESP32_DEFAULT_FIRMWARE_FILE=/etc/esp32/factory_default_firmware.tgz

LOGGER_PID=""

if [ -e /etc/jooki.conf ]; then
  source /etc/jooki.conf
fi

esp_reset() {
  echo -n "0" > /sys/kernel/htdrv/esp_bootmode
  echo -n "0" > /sys/kernel/htdrv/esp_reset

  if [ "x${ESP32_MMC_SPEED}" != "x" ]; then
    echo "${ESP32_MMC_SPEED}" > /sys/kernel/debug/${ESP32_MMC_DEV}/clock
  fi

  CLK=$(cat /sys/kernel/debug/${ESP32_MMC_DEV}/clock)
  logger -s "ESP32 SDIO clock: ${CLK}"

  /bin/sleep 0.1
  echo -n "1" > /sys/kernel/htdrv/esp_reset
}

program_firmware() {
  logger -s "Initialising ESP32 firmware..."

  ifconfig ethsta0 down || true
  modprobe -r ${ESP32_MODULE_NAME} || true

  /bin/sleep 0.1

  /usr/bin/ml-esp32-install-firmware.sh "${ESP32_DEFAULT_FIRMWARE_FILE}"
  if [ ! $? -eq 0 ]; then
    logger -s " failed to program ESP32 (1), retry..."
    /usr/bin/ml-esp32-install-firmware.sh "${ESP32_DEFAULT_FIRMWARE_FILE}"
    if [ ! $? -eq 0 ]; then
      logger -s " failed to program ESP32 (2) (OpenJooki: no factory mode flag)"
      exit 1
    fi
  fi
}

wait_for_esp() {
  logger -s "waiting for ESP32 to start..."
  local wait_ticks="${ESP32_MODULE_SLEEP_TIME}"

  until test $((wait_ticks--)) -eq 0 -o -e "/sys/bus/sdio/devices/mmc1:0001:2" ; do sleep 0.1; done
  if [ ! -e "/sys/bus/sdio/devices/mmc1:0001:2" ]; then
    logger -s " SDIO device not found"
    return 1
  fi

  sleep 0.1
  if [ ! -e /sys/kernel/esp32sdio/fw_version ]; then
    logger -s "ESP32 driver not present"
    return 3
  fi

  logger -s " checking ESP32 firmware version"
  wait_ticks="${ESP32_MODULE_SLEEP_TIME}"
  until test $((wait_ticks--)) -eq 0 -o $(cat /sys/kernel/esp32sdio/fw_version) -gt 0 ; do sleep 0.1; done
  ESP_FW_VERSION=$(cat /sys/kernel/esp32sdio/fw_version || echo "0")
  ESP_API_VERSION=$(cat /sys/kernel/esp32sdio/api_version || echo "0")
  if [ $ESP_FW_VERSION -gt 0 ]; then
    logger -s " ESP32 started, FW_VERSION=${ESP_FW_VERSION}, API_VERSION=${ESP_API_VERSION}"
    if [ -e /etc/esp32/esp_fw_version.rc ]; then
      source /etc/esp32/esp_fw_version.rc
      ESP32_FW_API_VERSION_DEC=$(printf "%d" ${ESP32_FW_API_VERSION})
      if [ "${ESP32_FW_API_VERSION_DEC}" -eq "${ESP_API_VERSION}" ]; then
        return 0
      else
        return 4
      fi
    fi
    return 0
  fi
  logger -s " ESP32 not started, FW_VERSION=${ESP_FW_VERSION}, API_VERSION=${ESP_API_VERSION}"
  return 2
}

start_logger() {
  if [ ! -z "${ESP32_LOG_FILE}" ]; then
    echo "=======================================================" >> "${ESP32_LOG_FILE}"
    echo "restart logging                                        " >> "${ESP32_LOG_FILE}"
    echo "=======================================================" >> "${ESP32_LOG_FILE}"
    cgexec -g cpu:background nice -n 10 ionice -c3 /usr/bin/esp32_tty_log.sh "${ESP32_LOG_FILE}" &
    LOGGER_PID="$!"
  elif [ ! -z "${ESP32_LOG_SYSLOG}" ]; then
    cgexec -g cpu:background nice -n 10 ionice -c3 /usr/bin/esp32_tty_log.sh &
    LOGGER_PID="$!"
  fi

}

if [ "x${ESP32_FIRMWARE_FORCE_LOAD}" == "x1" ]; then
  rm -f /data/mode/ESP32_FIRMWARE_LOADED || true
fi

if [ ! -e /data/mode/ESP32_FIRMWARE_LOADED ]; then
  program_firmware
fi

start_logger
logger -s "logger PID: $LOGGER_PID"

ifconfig ethsta0 down || true

if [ ! -e /data/mode/ESP32_FIRMWARE_LOADED ]; then
  modprobe ${ESP32_MODULE_NAME}
fi

wait_for_esp
rv=$?
if [ $rv -eq 4 ]; then
  logger -s "esp32 driver mismatch, reprogramming"
  rm -f /data/mode/ESP32_FIRMWARE_LOADED
  if [ ! -z "${LOGGER_PID}" ]; then
    kill ${LOGGER_PID} &
  fi
  program_firmware
  start_logger
elif [ $rv -gt 0 ]; then
  logger -s "error loading ESP32 driver (OpenJooki: no factory mode flag; the core retries the chip)"
  exit 1
fi

if [ ! -e /data/mode/ESP32_FIRMWARE_LOADED ]; then
  MAC=$(cat /sys/kernel/htdrv/mac)
  logger -s "Burning MAC address to ESP32 NVS..."
  /jooki/bin/esp32_cmd set_mac_addr 127 ${MAC}
  /jooki/bin/esp32_cmd set_mac_addr 1 ${MAC}

  sleep 1
  modprobe -r ${ESP32_MODULE_NAME} || true
  sleep 1
  esp_reset
  modprobe ${ESP32_MODULE_NAME}

  wait_for_esp
  if [ $? -gt 0 ]; then
    logger -s "error re-loading ESP32 driver (OpenJooki: no factory mode flag)"
  else
    touch /data/mode/ESP32_FIRMWARE_LOADED
  fi
fi

mkdir -p /run/esp32 || true

/jooki/bin/esp32_cmd set_versions

# OpenJooki: the factory network is not added any more. The chip keeps what it had: remove it,
# but only when a real network is remembered too (never leave the chip with no network at all).
KNOWN_APS=$(/jooki/bin/esp32_cmd list_configured_ap 2>/dev/null)
if echo "$KNOWN_APS" | grep -qw "$JOOKI_WIFI_DEFAULT_SSID" \
   && echo "$KNOWN_APS" | tr ',' '\n' | grep -v -w "$JOOKI_WIFI_DEFAULT_SSID" | grep -q '[^[:space:]"]'; then
  logger -s "OpenJooki: forgetting the factory network $JOOKI_WIFI_DEFAULT_SSID"
  /jooki/bin/esp32_cmd remove_ap "$JOOKI_WIFI_DEFAULT_SSID" > /dev/null 2>&1 || true
fi


airplane_mode=$(/jooki/bin/esp32_cmd get_airplane_mode)

if [ "$airplane_mode" == "enabled" ] && [ ! -r /data/mode/WIFI_OFF ]; then
  logger -s "disabling wifi, set WIFI_OFF flag"
  touch /data/mode/WIFI_OFF
  sync
  exit 0
elif [ "$airplane_mode" == "disabled" ]  && [ -r /data/mode/WIFI_OFF ]; then
  logger -s "enabling wifi, remove WIFI_OFF flag"
  rm -f /data/mode/WIFI_OFF
  sync
fi

if [ -r /data/mode/IN_PRODUCTION ]; then
  logger -s "Skip wifi due to IN_PRODUCTION flag"
  exit 0
fi

if [ -r /mnt/config/jooki.conf ]; then
	WIFI_CONFIGURATION_SSID=$(grep "^ESP_SSID" /mnt/config/jooki.conf | sed 's/ESP_SSID=//;s/^.//;s/.$//')
	WIFI_CONFIGURATION_PASSWORD=$(grep "^ESP_PWD" /mnt/config/jooki.conf | sed 's/ESP_PWD=//;s/^.//;s/.$//')

	if [ "$WIFI_CONFIGURATION_SSID" != "" ] && [ "$WIFI_CONFIGURATION_SSID" != "no_ssid" ]; then
		if [ "$WIFI_CONFIGURATION_PASSWORD" != "" ] && [ "$WIFI_CONFIGURATION_PASSWORD" != "no_password" ]; then
			FOUND_WIFI_SSID=$(/jooki/bin/esp32_cmd list_configured_ap | grep -w "$WIFI_CONFIGURATION_SSID")
			if [ -z "$FOUND_WIFI_SSID" ]; then
				logger -s "Adding legacy WiFi access point configuration from jooki.conf to ESP32 NVS."
				/jooki/bin/esp32_cmd add_ap "$WIFI_CONFIGURATION_SSID" "$WIFI_CONFIGURATION_PASSWORD"
				sed -i -e '/ESP_SSID/d' -e '/ESP_PWD/d' /mnt/config/jooki.conf
			fi
		fi
	fi
fi

if [ -r /data/mode/NO_APP ]; then
  MAC=$(cat /sys/kernel/htdrv/mac)

  logger -s "Bring up ethsta0"
  ifconfig ethsta0 down
  ifconfig ethsta0 hw ether ${MAC}
  ifconfig ethsta0 up

  if [ ! -f "/data/mode/DISABLE_DHCP" ]; then
    logger -s "Get DHCP lease..."
    /sbin/udhcpc -i ethsta0 -s /etc/udhcpc-update.sh -b &
  fi
fi
