#!/bin/ash
# OpenJooki: a Wi-Fi chip (ESP32) firmware on trial, with the way back built in (docs/32).
#
# The Jooki writes its chip by itself, without being opened: the original start script (S55) does
# it with /usr/bin/ml-esp32-install-firmware.sh (chip in download mode, esptool over the internal
# serial line) whenever its "firmware loaded" flag is missing. This script uses that same installer,
# at the same moment of the start (S55, before the chip's driver and logger are in use), first for
# the new firmware, then, if anything is wrong, for the original one, which stays on the Jooki
# (/etc/esp32/factory_default_firmware.tgz, and a checked copy on /data). Neither package writes the
# chip's settings (NVS, 0x9000-0xd000): the Wi-Fi networks stay.
#
#   oj-esp32-trial check <package>     read-only: is this Jooki ready for that package?
#   oj-esp32-trial install <package>   check, keep both packages on /data; written at the next start
#   oj-esp32-trial uninstall           back to the original firmware at the next start
#   oj-esp32-trial status              where the trial stands, and its log
#   oj-esp32-trial boot                called by S55 at every start (does nothing without a trial)
#
# The trial is accepted only when, after the new firmware's first start, the chip answers and the
# Wi-Fi gives Linux a route within wifi_s (10 min), and both still hold stable_s (2 min) later.
# Otherwise, and also after any restart before that, the original firmware is written back.
# Only the package whose SHA-256 is CANDIDATE is accepted, and only on a Jooki whose original
# package is STOCK (the one it was checked against): anything else is refused before any write.
set -u
export PATH=${OJ_ESP_PATH:-/sbin:/usr/sbin:/bin:/usr/bin}
DATA=${OJ_ESP_DATA:-/data}
DIR=$DATA/openjooki/esp32
STATE=$DIR/state
LOG=$DIR/log
CAND=$DIR/candidate.tgz
COPY=$DIR/stock.tgz
TRIES=$DIR/restore_tries
LOADED=$DATA/mode/ESP32_FIRMWARE_LOADED
STOCK_ETC=${OJ_ESP_STOCK:-/etc/esp32/factory_default_firmware.tgz}
INSTALLER=${OJ_ESP_INSTALLER:-/usr/bin/ml-esp32-install-firmware.sh}
API_RC=${OJ_ESP_API_RC:-/etc/esp32/esp_fw_version.rc}
FW_VERSION=${OJ_ESP_FW_VERSION:-/sys/kernel/esp32sdio/fw_version}
ROUTES=${OJ_ESP_ROUTES:-/proc/net/route}
HTDRV=${OJ_ESP_HTDRV:-/sys/kernel/htdrv}
WIFI_S=${OJ_ESP_WIFI_S:-600}
STABLE_S=${OJ_ESP_STABLE_S:-120}
STEP=${OJ_ESP_STEP:-10}
MIN_FREE_KB=8192
# tools/firmware: public SDK port + volume.patch + wifi-roaming.patch, package.py (reproducible)
CANDIDATE=494de2427059ed158428acd140a4afa5649e4306c48b54495f8f7574872f2a5a
# the original package of the Jookis checked so far (firmware 0x020C, API 0x0204)
STOCK=7af7a71f682aa410a43fe2c091094380abd449cc33ef5eb4efe0ccd1e2ed8c53
API=0x0204

say() {
  logger -t oj-esp32 "$1" 2>/dev/null
  mkdir -p "$DIR" 2>/dev/null
  # a short log: the last 200 lines
  { [ -f "$LOG" ] && tail -n 199 "$LOG"; echo "$(date '+%Y-%m-%d %H:%M:%S') $1"; } > "$LOG.new" 2>/dev/null &&
    mv -f "$LOG.new" "$LOG" 2>/dev/null
}
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
state() { [ -f "$STATE" ] && head -n 1 "$STATE" || echo none; }
set_state() {
  mkdir -p "$DIR" && echo "$1" > "$STATE.new" && mv -f "$STATE.new" "$STATE" && sync
}
alive() { v=$(cat "$FW_VERSION" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null; }
routed() { grep -q "^ethsta0[[:space:]]00000000[[:space:]]" "$ROUTES" 2>/dev/null; }

# check <package>: every condition, said one by one; 0 only when all hold
check() {
  ok=0
  bad() { echo "NOT OK  $1"; ok=1; }
  good() { echo "ok      $1"; }
  s=$(state)
  case "$s" in
    none|accepted|restored|failed*|restore-failed) good "no trial in progress ($s)" ;;
    *) bad "a trial is in progress ($s): finish it or uninstall first" ;;
  esac
  if [ -f "${1:-}" ] && [ "$(sha "$1")" = "$CANDIDATE" ]; then good "the new firmware package is the expected one"
  else bad "the new firmware package is not the expected one (SHA-256 $CANDIDATE)"; fi
  if [ -f "${1:-}" ] && tar -tzf "$1" > /dev/null 2>&1; then good "the new firmware package opens"
  else bad "the new firmware package does not open"; fi
  if [ "$(sha "$STOCK_ETC")" = "$STOCK" ]; then good "the original firmware is on the Jooki, intact"
  else bad "the original firmware package is missing or not the one this was checked against"; fi
  if grep -q "ESP32_FW_API_VERSION=\"$API\"" "$API_RC" 2>/dev/null; then good "the system expects chip API $API"
  else bad "the system does not expect chip API $API"; fi
  if [ -x "$INSTALLER" ]; then good "the Jooki's own installer is there"; else bad "no $INSTALLER"; fi
  if [ -e "$LOADED" ]; then good "the chip's firmware is marked as loaded"; else bad "the chip's firmware is not marked as loaded"; fi
  if alive; then good "the chip answers now"; else bad "the chip does not answer now"; fi
  if routed; then good "the Wi-Fi works now (it is how the trial is judged)"; else bad "no Wi-Fi now: the trial needs it"; fi
  free=$(df -k "$DATA" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$free" ] && [ "$free" -ge "$MIN_FREE_KB" ] 2>/dev/null; then good "room on $DATA (${free} KB free)"
  else bad "not enough room on $DATA"; fi
  return $ok
}

install_pkg() {
  check "${1:-}" || { echo "Nothing changed."; return 1; }
  mkdir -p "$DIR" || return 1
  rm -f "$TRIES"
  cp "$1" "$CAND.new" && cp "$STOCK_ETC" "$COPY.new" && sync || { rm -f "$CAND.new" "$COPY.new"; echo "Copy failed. Nothing changed."; return 1; }
  if [ "$(sha "$CAND.new")" != "$CANDIDATE" ] || [ "$(sha "$COPY.new")" != "$STOCK" ]; then
    rm -f "$CAND.new" "$COPY.new"; echo "The copies differ from the originals. Nothing changed."; return 1
  fi
  mv -f "$CAND.new" "$CAND" && mv -f "$COPY.new" "$COPY" && set_state staged || return 1
  say "staged: the new firmware is written at the next start"
  echo "Ready. Restart the Jooki: the new firmware is written at the start (the Wi-Fi takes about a"
  echo "minute more), and the original one comes back by itself if the chip or the Wi-Fi is not right."
}

uninstall() {
  case "$(state)" in
    staged) rm -f "$STATE" "$CAND"; say "trial cancelled before any write"; echo "Cancelled: nothing had been written." ;;
    accepted|trying|restore-failed) set_state restore; say "back to the original firmware asked"
       echo "The original firmware is written back at the next start: restart the Jooki." ;;
    *) echo "Nothing to undo ($(state))." ;;
  esac
}

# the chip back in normal mode, as the installer leaves it on success (it stops halfway on errors)
chip_normal() {
  echo -n 0 > "$HTDRV/esp_reset" 2>/dev/null; sleep 0.1
  echo -n 0 > "$HTDRV/esp_bootmode" 2>/dev/null; sleep 0.2
  echo -n 1 > "$HTDRV/esp_reset" 2>/dev/null
}

restore() {
  n=$(cat "$TRIES" 2>/dev/null || echo 0)
  if [ "$n" -ge 3 ] 2>/dev/null; then
    set_state restore-failed; say "the original firmware could not be written back, 3 starts in a row: giving up"
    chip_normal; return 1
  fi
  echo $((n + 1)) > "$TRIES"; sync
  set_state restoring
  pkg=
  if [ "$(sha "$COPY")" = "$STOCK" ]; then pkg=$COPY
  elif [ "$(sha "$STOCK_ETC")" = "$STOCK" ]; then pkg=$STOCK_ETC; fi
  if [ -z "$pkg" ]; then
    set_state restore-failed; say "no intact original firmware package: nothing written"; chip_normal; return 1
  fi
  say "writing the original firmware back ($1)"
  if "$INSTALLER" "$pkg" || "$INSTALLER" "$pkg"; then
    # S55 then starts the chip as after a factory write (driver, MAC address, flag)
    rm -f "$LOADED" "$TRIES"; set_state restored; say "the original firmware is back"
    return 0
  fi
  say "writing the original firmware failed (try $((n + 1)) of 3)"
  chip_normal; return 1
}

# after the new firmware's first start: judge it, in the background (S55 goes on)
watch() {
  (
    t=0
    while [ "$t" -lt "$WIFI_S" ]; do
      alive && routed && break
      sleep "$STEP"; t=$((t + STEP))
    done
    [ "$(state)" = trying ] || exit 0
    if alive && routed; then
      sleep "$STABLE_S"
      [ "$(state)" = trying ] || exit 0
      if alive && routed; then
        set_state accepted; say "accepted: the chip answers and the Wi-Fi works"; exit 0
      fi
      why="the chip or the Wi-Fi did not hold"
    elif alive; then why="no Wi-Fi within ${WIFI_S} s"
    else why="the chip does not answer"; fi
    set_state restore; say "not accepted: $why; restarting to write the original firmware back"
    reboot
  ) < /dev/null > /dev/null 2>&1 &
}

boot() {
  case "$(state)" in
    staged)
      if [ "$(sha "$CAND")" != "$CANDIDATE" ] || [ "$(sha "$COPY")" != "$STOCK" ]; then
        set_state failed-damaged; say "a package on /data is damaged: nothing written"; return 0
      fi
      set_state flashing; say "writing the new firmware"
      if "$INSTALLER" "$CAND"; then
        rm -f "$LOADED"; set_state trying; say "new firmware written, judging its first start"
        watch
      else
        say "writing the new firmware failed"; restore "the write failed"
      fi ;;
    flashing) restore "the Jooki stopped while writing" ;;
    trying) restore "a restart before the trial was accepted" ;;
    restore|restoring) restore "asked" ;;
  esac
  return 0
}

case "${1:-}" in
  check) check "${2:-}" ;;
  install) install_pkg "${2:-}" ;;
  uninstall) uninstall ;;
  status) echo "state: $(state)"; [ -f "$LOG" ] && tail -n 20 "$LOG" ;;
  boot) boot ;;
  stock-back) [ "$(state)" = trying ] && { set_state restored; say "S55 wrote the original firmware back (API mismatch)"; } ; exit 0 ;;
  *) echo "usage: oj-esp32-trial check|install <package> | uninstall | status"; exit 2 ;;
esac
