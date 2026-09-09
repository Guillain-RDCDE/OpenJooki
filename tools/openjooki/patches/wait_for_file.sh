#! /bin/ash
# OpenJooki: ajout d'un timeout (defaut 120s) pour ne plus attendre a l'infini.
set -eu
file="$1"; timeout="${2:-120}"
echo "Wait for: $file (timeout ${timeout}s)"
i=0
while [ ! -e "$file" ]; do
    i=$((i+1))
    if [ "$i" -ge "$timeout" ]; then echo "Timeout: $file" >&2; exit 1; fi
    sleep 1
done
echo "Found: $file"
