#!/usr/bin/env bash
# jooki-backup.sh — backup of the Jooki v2 (run from the Mac)
# Requires: root SSH access to the Jooki (see docs/05-runbook-phase0.md)
set -euo pipefail

JOOKI="${JOOKI:-jooki}"
SSH="ssh -o BatchMode=yes $JOOKI"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"

usage(){ cat <<U
Usage: $0 <command>
  info     Jooki system info (hardware, disks, mender)
  data     Backup of the DATA (json, uploads, artwork, config, ESP32 fw, web UI)
  image    FULL IMAGE of the SD card ("gold" backup, ~2-3 GB compressed)
  verify   Verifies the latest image (gzip -t + size)
Variables: JOOKI=$JOOKI  (overridable)
U
}

cmd_info(){
  echo "== Jooki: $JOOKI =="
  $SSH 'echo "--- uname ---"; uname -a;
        echo "--- cpuinfo (end) ---"; tail -n 15 /proc/cpuinfo 2>/dev/null;
        echo "--- lsblk ---"; lsblk 2>/dev/null || cat /proc/partitions;
        echo "--- df ---"; df -h;
        echo "--- mender ---"; cat /etc/mender/mender.conf 2>/dev/null;
        echo "--- flags ---"; ls -1 /data/mode/ 2>/dev/null;
        echo "--- versions ---"; cat /jooki/*version* 2>/dev/null'
}

cmd_data(){
  local d="$OUT/data-$STAMP"; mkdir -p "$d"
  echo "== Data backup -> $d =="
  # 1) Content JSON + config (small, critical)
  echo "[1/4] json + config"
  $SSH 'tar czf - \
        /jooki/playlists.json /jooki/tokens.json /jooki/tokens.json.bak \
        /jooki/audiocfg.json /jooki/playstate.json \
        /mnt/config/jooki.conf 2>/dev/null' > "$d/jooki-json-config.tar.gz" || true
  # 2) uploads + artwork (the MP3s and covers)
  echo "[2/4] uploads + artwork (may take a while)"
  $SSH 'tar czf - /jooki/uploads /jooki/artwork 2>/dev/null' > "$d/jooki-media.tar.gz" || true
  # 3) ESP32 firmware + services (heartbeat, etc.)
  echo "[3/4] ESP32 firmware + app/services"
  $SSH 'tar czf - $(find / -iname "*.bin" -path "*esp*" 2>/dev/null) \
        /jooki/app/services 2>/dev/null' > "$d/jooki-fw-services.tar.gz" || true
  # 4) web UI bundle (to re-host/patch later)
  echo "[4/4] web UI"
  $SSH 'tar czf - $(find / -type d \( -iname "www" -o -iname "webui" -o -iname "public" \) 2>/dev/null | head -5) 2>/dev/null' > "$d/jooki-webui.tar.gz" || true
  echo "Done. Contents:"; ls -lh "$d"
}

cmd_image(){
  mkdir -p "$OUT"
  local f="$OUT/jooki-sd-$STAMP.img.gz"
  echo "== FULL IMAGE of /dev/mmcblk0 -> $f =="
  echo "   (the Jooki must be idle; this takes several minutes)"
  $SSH 'gzip -1 -c < /dev/mmcblk0' > "$f"
  echo "Image written: $(ls -lh "$f" | awk '{print $5, $9}')"
  echo "Remember to run: $0 verify"
}

cmd_verify(){
  local last; last="$(ls -t "$OUT"/jooki-sd-*.img.gz 2>/dev/null | head -1 || true)"
  [ -z "$last" ] && { echo "No image found in $OUT"; exit 1; }
  echo "Verifying: $last"
  gzip -t "$last" && echo "OK: gzip archive intact. Size: $(ls -lh "$last" | awk '{print $5}')"
}

case "${1:-}" in
  info) cmd_info;;
  data) cmd_data;;
  image) cmd_image;;
  verify) cmd_verify;;
  *) usage; exit 1;;
esac
