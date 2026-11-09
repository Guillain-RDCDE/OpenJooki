#!/bin/ash
# OpenJooki guard: a system that starts but whose core does not. The rollback of an update only
# covers a kernel that does not boot, and the update is committed 30 s after the boot whatever the
# core does: a core that fails to start left a Jooki with no page, no tokens and no way back but
# opening it. Here: if the core's page has not answered, twice, some minutes after the boot, the
# Jooki goes back to its other system partition by itself, once. Music and settings are on other
# partitions and stay.
#
# Installed as /etc/rcS.d/S95_oj-guard.sh. rcS sources it, so everything runs in the background.
# It only reads and changes the bootloader's choice of partition (the method of docs/04), and only
# towards a partition that holds a kernel and a core. It never goes back to the partition it just
# fled: two bad systems stay where they are instead of restarting for ever.
(
  export PATH=${OJ_GUARD_PATH:-/sbin:/usr/sbin:/bin:/usr/bin}
  LIMIT=${OJ_GUARD_LIMIT:-300}      # seconds after this script starts, the core's page must answer
  STEP=${OJ_GUARD_STEP:-10}
  SECOND=${OJ_GUARD_SECOND:-20}     # the second answer, this long after the first: a core that stays up
  DATA=${OJ_GUARD_DATA:-/data}
  URL=${OJ_GUARD_URL:-http://127.0.0.1/}
  PART=${OJ_GUARD_PART:-/dev/mmcblk0p}
  MNT=${OJ_GUARD_MNT:-/run/oj-guard}
  MARK=$DATA/openjooki/guard_fled

  say() { logger -t oj-guard "$1" 2>/dev/null; }
  page() { curl -s -f -m 5 -o /dev/null "$URL" 2>/dev/null; }

  [ -e "$DATA/mode/NO_APP" ] && exit 0

  waited=0
  while [ "$waited" -lt "$LIMIT" ]; do
    if page; then
      sleep "$SECOND"
      if page; then
        rm -f "$MARK"
        say "the core answers"
        exit 0
      fi
    fi
    sleep "$STEP"; waited=$((waited + STEP))
  done

  say "the core's page did not answer in ${LIMIT} s"
  cur=$(fw_printenv mender_boot_part 2>/dev/null | sed 's/.*=//')
  case "$cur" in
    2) other=3 ;;
    3) other=2 ;;
    *) say "booted from partition '$cur': nothing to do"; exit 0 ;;
  esac
  if [ "$(cat "$MARK" 2>/dev/null)" = "$other" ]; then
    say "partition $other failed too, just before this one: staying here"
    exit 0
  fi

  # only towards a partition that can start
  mkdir -p "$MNT"
  mount -o ro "$PART$other" "$MNT" 2>/dev/null || { say "partition $other cannot be mounted: staying here"; exit 0; }
  ok=1
  for f in boot/uImage jooki/lib/player.lib jooki/bin/player; do
    [ -e "$MNT/$f" ] || ok=0
  done
  umount "$MNT" 2>/dev/null
  [ "$ok" = 1 ] || { say "partition $other is not a complete system: staying here"; exit 0; }

  mkdir -p "$DATA/openjooki"
  echo "$cur" > "$MARK"; sync
  say "going back to partition $other"
  { echo "mender_boot_part $other"; echo "mender_boot_part_hex $other"
    echo "upgrade_available 0"; echo "bootcount 0"; } > "$MNT.env"
  fw_setenv -s "$MNT.env" || { rm -f "$MARK"; say "the bootloader settings could not be written: staying here"; exit 0; }
  [ "$(fw_printenv mender_boot_part 2>/dev/null | sed 's/.*=//')" = "$other" ] || { rm -f "$MARK"; say "the settings did not hold: staying here"; exit 0; }
  sync
  reboot
) </dev/null >/dev/null 2>&1 &
