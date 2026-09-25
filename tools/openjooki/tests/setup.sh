#!/bin/bash
# Build a fake Jooki filesystem so the real Lua app can run on this machine.
set -e
rm -rf /jooki /tmp/web_ctrl_dirs /data/mode
mkdir -p /jooki/external/jooki/uploads /jooki/external/jooki/artwork /jooki/app/system/assets /jooki/app/services /jooki/app/www/public /jooki/app/www/wifi_setup/public /jooki/app/www/deezer /data/mode /mnt/config
S=/jooki/app/services
for f in errorbeep.sh heartbeat.sh lang_set.sh toy_safe_update.sh radio.sh wifi_signal.sh speak_info.sh record.sh power_overheat.sh factory_reset.sh factory_reset_wifi.sh wifi_add_network.sh fast_restart.sh suspend.sh stop_process_and_wait.sh; do printf '#!/bin/sh\necho "STUB $0 $*" >> /tmp/bench_services.log\nexit 0\n' > $S/$f; done
printf '#!/bin/sh\necho 10.0.0.2\n' > $S/wifi_ip.sh
printf '#!/bin/sh\nexit 0\n' > $S/is_mounted.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
cat > $S/ml-audio-probe-wrapper.sh <<P
#!/bin/sh
exec python3 $HERE/probe.py "\$@"
P
chmod 755 $S/*
# system catalog (read-only) : empty db
for f in playlists tracks tokens; do echo '{"_":{"version":1}}' > /jooki/app/system/$f.json; done
echo '{"_":{"version":1}}' > /jooki/app/system/playlists.json
# user db
for f in playlists tracks tokens; do echo '{"_":{"version":1}}' > /jooki/external/jooki/$f.json; done
echo 1.0.0 > /etc/openjooki-version   # installed OpenJooki version (the page offers the GitHub latest)
rm -f /tmp/oj-updating
echo ok
