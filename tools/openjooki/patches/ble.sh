#! /bin/ash
# Modifie par OpenJooki : backdoors d'execution de code (u/userset, _/custom) neutralisees.
set -eu
cd "$(dirname "$0")"
OUT=/tmp/ble.txt
rm -f $OUT
arg="$1"
echo "$arg" >> /tmp/ble_in.txt
cmd="${arg:0:1}"
ok() { echo -n "OK" > $OUT; }
wifisetup() {
    ssid_hex="$(echo "$arg" | cut -f 2)"
    ssid=""
    pass="$(echo "$arg" | cut -f 3)"
    lang="$(echo "$arg" | cut -f 4)"
    ./wifi_add_network.sh "$ssid_hex" "$ssid" "$pass" "$lang"
    ok
}
case "$cmd" in
    0) cp /etc/mender/artifact_info $OUT ;;
    1) cp /tmp/wifi_scan.txt $OUT ;;
    2) ./wifi_scan.sh ;;
    3) wifisetup ;;
    e) journalctl | grep CFG80211 | tail -n 3 > $OUT ;;
    u) echo "OpenJooki: commande desactivee" > $OUT ;;
    w) iw wlan0 link | grep 'SSID\|Not' > $OUT ;;
    _) echo "OpenJooki: commande desactivee" > $OUT ;;
    *)   echo "invalid cmd '$cmd'"; exit 1
esac
