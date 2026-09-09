#!/bin/bash
# OpenJooki — prepares a release (compressed image + sha256 + version.json).
# Usage: make-release.sh <image.img[.gz]> <version>
set -e
IMG="$1"; VER="$2"
[ -f "$IMG" ] && [ -n "$VER" ] || { echo "usage: make-release.sh <image.img[.gz]> <version>"; exit 1; }
command -v sha256sum >/dev/null 2>&1 && SHA="sha256sum" || SHA="shasum -a 256"
OUT="release-$VER"; mkdir -p "$OUT"
FILE="openjooki-firmware-$VER.img.gz"
case "$IMG" in *.gz) cp "$IMG" "$OUT/$FILE";; *) gzip -c "$IMG" > "$OUT/$FILE";; esac
HASH=$($SHA "$OUT/$FILE" | cut -d' ' -f1)
cat > "$OUT/version.json" <<EOF
{
  "version": "$VER",
  "file": "$FILE",
  "sha256": "$HASH",
  "date": "$(date +%Y-%m-%d)"
}
EOF
echo "Release ready in $OUT/ :"; ls -la "$OUT"
echo "→ GitHub Release tag v$VER, attach $FILE AND version.json."
