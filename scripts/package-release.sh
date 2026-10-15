#!/bin/bash
# Produces distribution artifacts locally. Publishing is a separate, explicit step.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COULEUR_NOTARY_PROFILE:?Set COULEUR_NOTARY_PROFILE to a notarytool Keychain profile}"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the reviewed source before packaging a public release.' >&2; exit 1; }
notary_args=(--keychain-profile "$COULEUR_NOTARY_PROFILE")
if [[ -n "${COULEUR_NOTARY_KEYCHAIN:-}" ]]; then notary_args+=(--keychain "$COULEUR_NOTARY_KEYCHAIN"); fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build_number" =~ ^[0-9]+$ ]] || { echo 'Invalid version/build' >&2; exit 1; }
python3 scripts/check-release-version.py
dist="build/releases/$version"
[[ ! -e "$dist" ]] || { echo "Already exists: $dist. Move it aside before rebuilding; published bytes must never change." >&2; exit 1; }
identity="${COULEUR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application:/ {print $2; exit}')}"
[[ -n "$identity" ]] || { echo 'Developer ID Application certificate and private key required.' >&2; exit 1; }
export COULEUR_SIGN_IDENTITY="$identity" COULEUR_DISTRIBUTION=1
swift package resolve
sparkle_tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # Sparkle includes malformed input in its error. Reject it without printing secrets.
  python3 - <<'PY'
import os, base64
try:
    assert len(base64.b64decode(os.environ['SPARKLE_PRIVATE_KEY'].strip(), validate=True)) in (32, 96)
except Exception:
    raise SystemExit('Invalid Sparkle private key encoding')
PY
else
  actual_key=$("$sparkle_tools/generate_keys" --account com.aymeric.couleur -p)
  expected_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)
  [[ "$actual_key" == "$expected_key" ]] || { echo 'Sparkle Keychain key does not match this app.' >&2; exit 1; }
fi
mkdir -p "$dist" build/notarization
xcrun notarytool history "${notary_args[@]}" --output-format json > build/notarization/preflight.json
swift test
./scripts/build.sh release universal
app="$PWD/build/Couleur.app"
work=$(mktemp -d "$PWD/build/release-work.XXXXXX")
trap 'rm -rf "$work"' EXIT
notarize() {
  local artifact="$1" name="$2" response="$PWD/build/notarization/$version-$2.json"
  xcrun notarytool submit "$artifact" "${notary_args[@]}" --wait --output-format json > "$response"
  if ! python3 - "$response" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
sys.exit(0 if result.get('status') == 'Accepted' else 1)
PY
  then
    echo "Apple did not accept $name. Inspect $response and retrieve the notary log before retrying." >&2; exit 1
  fi
}
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/submission.zip"
notarize "$work/submission.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose "$app"
mkdir -p "$work/updates" "$work/dmg"
archive="Couleur-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/updates/$archive"
ditto "$app" "$work/dmg/Couleur.app"
ln -s /Applications "$work/dmg/Applications"
hdiutil create -volname Couleur -srcfolder "$work/dmg" -format UDZO -fs HFS+ "$dist/Couleur-$version.dmg"
codesign --force --sign "$identity" --timestamp "$dist/Couleur-$version.dmg"
notarize "$PWD/$dist/Couleur-$version.dmg" dmg
xcrun stapler staple "$dist/Couleur-$version.dmg"
xcrun stapler validate "$dist/Couleur-$version.dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dist/Couleur-$version.dmg"
feed_args=(--download-url-prefix "https://github.com/Aymericr/couleur/releases/download/v$version/" --maximum-deltas 0 --versions "$build_number" -o "$PWD/$dist/appcast.xml" "$work/updates")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_tools/generate_appcast" --ed-key-file - "${feed_args[@]}"
else
  "$sparkle_tools/generate_appcast" --account com.aymeric.couleur "${feed_args[@]}"
fi
cp "$work/updates/$archive" "$dist/$archive"
swift scripts/verify-update.swift "$app/Contents/Info.plist" "$dist/$archive" "$dist/appcast.xml"
python3 scripts/release-metadata.py "$dist" Resources/Info.plist
ruby -c "$dist/couleur.rb"
echo "Verified release artifacts: $PWD/$dist"
