#!/bin/ash


set -eu
. /etc/jooki.conf

ensure_mtd_dev() {
    mtd_dev="/dev/mtd1"
    mtd_minor=2
    if [ ! -e ${mtd_dev} ]; then
        /bin/mknod -m 0600 ${mtd_dev} c 90 ${mtd_minor}
    fi
}

mac=""
get_mac() {
  if [ "${JOOKI_MACHINE}" == "ml-j1000" ]; then
    ensure_mtd_dev
    mac=$(fw_printenv | grep 'mac_1' | sed -e 's/mac_1=//')
  elif [ "${JOOKI_MACHINE}" == "ml-j2000" ]; then
    mac=$(cat /sys/kernel/htdrv/mac)
  fi
  echo ${mac}
}

hostname=""

get_hostname() {
  get_mac
  if [ "${JOOKI_MACHINE}" == "ml-j1000" ]; then
    mac4=$(echo "$mac" | sed 's/://g' | tail -c5)
    hostname="jooki-$mac4"
  elif [ "${JOOKI_MACHINE}" == "ml-j2000" ]; then
    mac6=$(echo "$mac" | sed 's/://g' | tail -c7)
    hostname="jooki2-$mac6"
  fi
}

write_hostname() {
    get_hostname
    echo "$hostname" > /etc/hostname
    echo "$mac" > /etc/mac
    # OpenJooki: the name chosen on the page (/data survives updates), if valid; otherwise the
    # factory name. /etc/hostname always keeps the factory name: it is the device id.
    name="$(head -n 1 /data/openjooki/hostname 2>/dev/null || true)"
    if [ "${#name}" -le 32 ] && echo "$name" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
      hostname "$name"
    else
      hostname "$(cat /etc/hostname)"
    fi
    sync
}

write_hostname
