if [ -e /etc/jooki.conf ]; then
  source /etc/jooki.conf
fi

# OpenJooki: the original also used /mnt/config/mosquitto.conf when present. That partition is the
# card's FAT one, which any computer can write: a file dropped there replaced the broker's settings
# (and the page's password). The broker now always starts from its own settings (docs/adr/0007).
/bin/rm -f /var/run/mosquitto.pid

/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf -d
