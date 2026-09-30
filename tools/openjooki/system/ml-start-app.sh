#!/bin/ash
source /etc/jooki.conf

if [ -e /data/mode/NO_APP ]; then
  exit 0
fi

source /jooki/app/services/setinfo

/jooki/bin/ml-launch-controller.sh /jooki/bin/gpio_ctrl -5 &
/jooki/bin/ml-launch-controller.sh /jooki/bin/ht_ctrl -1 &
/jooki/bin/ml-launch-controller.sh /jooki/bin/esp32_ctrl -5 &

# OpenJooki: no 1 s wait here any more. The original waited for esp32_ctrl before starting the
# player; the 2.0 core says its boot orders to the ESP32 again at 1.5, 3 and 6 s by itself.
/jooki/bin/ml-launch-controller.sh /jooki/bin/player -6 &

# OpenJooki: web_ctrl is NOT started any more. It answered /ll (a root shell over HTTP) and /cmd
# (reboot, factory reset, format) to anyone on the Wi-Fi, without a password (docs/adr/0007). The
# 2.0 core serves the page and /upload itself (adapters.httpd, port 80); maintenance SSH is opened
# from the page over the WebSocket. So /ll and /cmd are simply gone.
