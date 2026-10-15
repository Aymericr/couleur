#!/bin/bash
# Default: a reviewable draft. --publish is the explicit public release step.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: publish-release.sh VERSION [--publish]}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
mode="${2:---draft}"
[[ "$mode" == --draft || "$mode" == --publish ]] || exit 1
repo=Aymericr/couleur
tag="v$version"
dist="$PWD/build/releases/$version"
[[ -z "$(git status --porcelain)" ]] || { echo 'Refusing to publish from a modified checkout.' >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-list -n 1 "$tag")" ]] || { echo 'Checkout must match the release tag.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)" == "$version" ]] || exit 1
[[ "$(gh repo view "$repo" --json visibility --jq .visibility)" == PUBLIC ]] || { echo 'The release repository must be public first.' >&2; exit 1; }
(cd "$dist" && shasum -a 256 -c SHA256SUMS)
xcrun stapler validate "$dist/Couleur-$version.dmg"
swift scripts/verify-update.swift Resources/Info.plist "$dist/Couleur-$version.zip" "$dist/appcast.xml"
if gh release view "$tag" --repo "$repo" --json isDraft > "$dist/release-state.json" 2>/dev/null; then
  python3 - "$dist/release-state.json" <<'PY'
import json,sys
if not json.load(open(sys.argv[1]))['isDraft']:
    raise SystemExit('Already published. Create a new version; never replace published assets.')
PY
else
  gh release create "$tag" --repo "$repo" --verify-tag --draft --title "Couleur $version" --generate-notes
fi
gh release upload "$tag" --repo "$repo" --clobber "$dist/Couleur-$version.dmg" "$dist/Couleur-$version.zip" "$dist/appcast.xml" "$dist/SHA256SUMS" "$dist/couleur.rb"
check=$(mktemp -d "$PWD/build/release-download.XXXXXX")
trap 'rm -rf "$check"' EXIT
gh release download "$tag" --repo "$repo" --dir "$check"
(cd "$check" && shasum -a 256 -c SHA256SUMS)
cmp "$dist/SHA256SUMS" "$check/SHA256SUMS"
if [[ "$mode" == --publish ]]; then
  gh release edit "$tag" --repo "$repo" --draft=false --latest
fi
echo "Release $tag: $mode. Assets downloaded and verified."
