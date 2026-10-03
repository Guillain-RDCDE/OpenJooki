# Making a release

Four scripts, in this order. Nothing is written by hand except the CHANGELOG entry and the
README's one-line summary; the version number itself is written once by the first script and
checked everywhere by CI (`scripts/check_versions.py`).

| Step | Where | Command |
|---|---|---|
| 1. Write the entry | anywhere | `CHANGELOG.md`: fill the `## Next release` section (one bullet per change a family can see) |
| 2. Set the version | anywhere | `scripts/bump-version.sh 2.2.6 "Title" "one-line summary"` then `git commit -am "Release 2.2.6: Title"` and `git push` |
| 3. Build | the Linux bench, as root | `scripts/release.sh 2.2.6` → `release-2.2.6/` (image + `version.json`) and `release-sdcard-2.2.6/` (new-card image + `sdcard.json`), both verified |
| 4. Publish | a machine with `gh` | `scripts/publish-release.sh 2.2.6` → tag, GitHub Release marked *Latest* (notes from the CHANGELOG entry), the rolling `sdcard` release updated, the published image downloaded again and checked |
| 5. Check the card | the bench | `scripts/check-card.sh 2.2.6` → the SD tool fetches the new-card image from the real release and writes an 8 GB "card" that is then checked |

What `release.sh` needs on the bench, by environment variable (defaults in the script): the
1.3.0 base image (`OJ_BASE_IMAGE`), the pieces of a new card (`OJ_NEWCARD`: `boot.bin`, `p1.img`;
`OJ_DATA_TAR`), and optionally `OJ_FORGET_FILE`, one string per line that must not appear in any
image (the source Jooki's own name, address and network: the build fails if one is found).

CI (`.github/workflows/ci.yml`) must be green on the pushed commit before step 4; the tag then
runs the long `nightly.yml` (the whole bench plus 10 minutes of endurance). Where the files go
and what the Jooki does with them: [15-ota-github.md](15-ota-github.md); the new card:
[25-new-sd-card.md](25-new-sd-card.md).

Two things `publish-release.sh` learnt the hard way: `gh release create` sometimes reports a TLS
timeout after the upload went through (it checks the release exists before retrying), and the
`sdcard` release keeps exactly one image (the previous one is deleted after the new one is up).
