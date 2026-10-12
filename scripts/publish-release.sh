#!/bin/bash
# OpenJooki — publish a release built by scripts/release.sh: the tag, the GitHub Release (marked
# Latest, notes from CHANGELOG.md; the image, version.json and the two updater scripts, each
# downloaded again and checked) and the rolling `sdcard` release (new image in, old one out).
# Needs gh (logged in) and the two release-* folders; runs anywhere (the maintainer's PC).
#
#   scripts/publish-release.sh 2.2.6
set -e
cd "$(dirname "$0")/.."
V="$1"; [ -n "$V" ] || { echo "usage: $0 <version>"; exit 1; }
REPO="Guillain-RDCDE/OpenJooki"
IMG="release-$V/openjooki-firmware-$V.img.gz"; MAN="release-$V/version.json"
# the updater scripts o.sh and b.sh fetch from the release first (version.json gives their sha256)
UPDATERS="openjooki-ota.sh openjooki-selfupdate.sh"
OTA="release-$V/openjooki-ota.sh"; SELF="release-$V/openjooki-selfupdate.sh"
CARD="release-sdcard-$V/openjooki-sdcard-$V.img.gz"; CARDMAN="release-sdcard-$V/sdcard.json"
for f in "$IMG" "$MAN" "$OTA" "$SELF" "$CARD" "$CARDMAN"; do [ -f "$f" ] || { echo "missing: $f (scripts/release.sh $V first)"; exit 1; }; done
command -v gh >/dev/null || { echo "gh is needed"; exit 1; }
python3 scripts/check_versions.py --release "$V" --manifest "$MAN"
[ -z "$(git status --porcelain)" ] || { echo "the tree is not clean: commit first"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "not on main"; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD is not pushed (or behind origin/main)"; exit 1; }
grep -q "\"version\": \"$V\"" "$MAN" || { echo "$MAN is not $V"; exit 1; }

# release notes: the CHANGELOG entry, its heading as a bold first line, then the standing footer
NOTES=$(mktemp)
awk -v v="$V" '
  /^## / { if (on) exit; if ($0 ~ "^## OpenJooki " v " ") { on = 1; sub(/^## /, ""); print "**" $0 "**"; print ""; next } }
  on { print }' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "no CHANGELOG entry for $V"; exit 1; }
printf '\nUpdate straight from your Jooki'"'"'s page. [All the changes](https://github.com/%s/blob/main/CHANGELOG.md).\n' "$REPO" >> "$NOTES"

echo "=== tag v$V"
if git rev-parse -q --verify "refs/tags/v$V" >/dev/null; then echo "tag exists"; else git tag -a "v$V" -m "OpenJooki $V"; fi
git push -q origin "v$V"

echo "=== GitHub release v$V"
if gh release view "v$V" -R "$REPO" >/dev/null 2>&1; then
  echo "release exists: uploading the assets again (--clobber)"
  gh release upload "v$V" "$IMG" "$MAN" "$OTA" "$SELF" --clobber -R "$REPO"
else
  # gh sometimes reports a TLS timeout after the upload went through: check before retrying
  gh release create "v$V" "$IMG" "$MAN" "$OTA" "$SELF" --verify-tag --title "OpenJooki $V" --notes-file "$NOTES" --latest -R "$REPO" \
    || { sleep 5; gh release view "v$V" -R "$REPO" >/dev/null; }
fi
rm -f "$NOTES"

echo "=== the published image, downloaded again"
TMP=$(mktemp); curl -sL -o "$TMP" "https://github.com/$REPO/releases/download/v$V/openjooki-firmware-$V.img.gz"
WANT=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['sha256'])" "$MAN")
GOT=$(sha256sum "$TMP" | cut -d' ' -f1); rm -f "$TMP"
[ "$GOT" = "$WANT" ] || { echo "sha256 of the published image differs: $GOT != $WANT"; exit 1; }
curl -sL "https://github.com/$REPO/releases/latest/download/version.json" | grep -q "\"version\": \"$V\"" || { echo "latest/version.json is not $V yet"; exit 1; }
# the updater scripts, as a Jooki gets them (latest/download/), against the manifest's sha256
for s in $UPDATERS; do
  case "$s" in openjooki-ota.sh) FIELD=ota_sha256;; *) FIELD=selfupdate_sha256;; esac
  WANT=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$MAN" "$FIELD")
  TMP=$(mktemp); curl -fsL -o "$TMP" "https://github.com/$REPO/releases/latest/download/$s" || { rm -f "$TMP"; echo "latest/$s cannot be downloaded"; exit 1; }
  GOT=$(sha256sum "$TMP" | cut -d' ' -f1); rm -f "$TMP"
  [ "$GOT" = "$WANT" ] || { echo "latest/$s: sha256 $GOT, the manifest says $WANT ($FIELD)"; exit 1; }
done
echo "image, latest manifest and updater scripts verified"

echo "=== rolling sdcard release"
gh release upload sdcard "$CARD" "$CARDMAN" --clobber -R "$REPO"
for old in $(gh release view sdcard -R "$REPO" --json assets --jq '.assets[].name' | grep '^openjooki-sdcard-' | grep -v "openjooki-sdcard-$V.img.gz"); do
  gh release delete-asset sdcard "$old" --yes -R "$REPO"; echo "removed $old"
done
BODY=$(gh release view sdcard -R "$REPO" --json body --jq .body)
NEW=$(printf '%s' "$BODY" | sed -E "s/\*\*Current image: OpenJooki [0-9.]+\*\* \([0-9]+ [A-Za-z]+ [0-9]{4}\)\./**Current image: OpenJooki $V** ($(LC_ALL=C date '+%-d %B %Y'))./")
[ "$NEW" != "$BODY" ] && gh release edit sdcard --notes "$NEW" -R "$REPO" >/dev/null && echo "sdcard notes: current image $V"
curl -sL "https://github.com/$REPO/releases/download/sdcard/sdcard.json" | grep -q "\"version\": \"$V\"" || { echo "sdcard.json is not $V yet"; exit 1; }
echo
echo "published: https://github.com/$REPO/releases/tag/v$V  (then scripts/check-card.sh $V on the bench)"
