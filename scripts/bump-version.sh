#!/bin/bash
# OpenJooki — write the next version number everywhere it is written by hand, in one go.
#   scripts/bump-version.sh 2.2.6 "Settings pages stay still" "the pages inside Settings no longer blink"
# Changes: webui/app.js VERSION, webui/index.html (three ?v=), CHANGELOG.md ("## Next release" becomes
# the release heading, dated today), README.md ("New in X" line: the new one on top, the old one demoted).
# Then scripts/check_versions.py --release confirms. Commit the result as "Release X: title".
set -e
cd "$(dirname "$0")/.."
V="$1"; TITLE="$2"; SUMMARY="$3"
[ -n "$V" ] && [ -n "$TITLE" ] && [ -n "$SUMMARY" ] || { echo "usage: $0 <version> \"<title>\" \"<one-line summary for the README>\""; exit 1; }
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "not a version: $V"; exit 1; }
grep -q '^## Next release$' CHANGELOG.md || { echo "CHANGELOG.md has no '## Next release' section to turn into $V"; exit 1; }
OLD=$(sed -n "s/^  var VERSION = '\([^']*\)';/\1/p" tools/openjooki/webui/app.js)
[ -n "$OLD" ] || { echo "no VERSION in app.js"; exit 1; }
DATE=$(LC_ALL=C date "+%-d %B %Y")

sed -i "s/^  var VERSION = '$OLD';/  var VERSION = '$V';/" tools/openjooki/webui/app.js
sed -i "s/?v=$OLD\"/?v=$V\"/g" tools/openjooki/webui/index.html
sed -i "s/^## Next release$/## OpenJooki $V ($DATE) — $TITLE/" CHANGELOG.md
# README: "**New in OLD:** text" -> "**New in V:** summary." then "OLD: text"
python3 - "$V" "$OLD" "$SUMMARY" <<'EOF'
import re, sys
v, old, summary = sys.argv[1:4]
s = open("README.md", encoding="utf-8").read()
new, n = re.subn(r"^\*\*New in %s:\*\* " % re.escape(old), "**New in %s:** %s.\n%s: " % (v, summary.rstrip("."), old), s, count=1, flags=re.M)
assert n == 1, "README.md: no '**New in %s:**' line" % old
open("README.md", "w", encoding="utf-8", newline="").write(new)
EOF
python3 scripts/check_versions.py --release "$V"
echo "bumped $OLD -> $V. Review CHANGELOG.md and README.md, then: git commit -am \"Release $V: $TITLE\""
