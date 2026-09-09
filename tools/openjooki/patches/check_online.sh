#! /bin/ash
# Modifie par OpenJooki : ne depend plus du serveur cloud (my.jooki.rocks) mort.
# Plus de boucle infinie sur un ping mort ; on lance le heartbeat (no-op) directement.
set -eu
cd "$(dirname "$0")"
. ./log
log "OpenJooki: online check local (cloud desactive)"
/jooki/app/services/heartbeat.sh S_LIVE &
