#! /bin/ash
# OpenJooki: grep ancre (fixed-string, delimite) pour eviter les faux positifs de montage.
if mount | grep -qF " $1 "; then
    echo "$1 is mounted"; exit 0
else
    echo "$1 is not mounted"; exit 1
fi
