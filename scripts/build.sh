#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
architecture="${2:-native}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
  echo "Usage: scripts/build.sh [release|debug] [native|universal]" >&2
  exit 1
fi
args=(-c "$configuration")
case "$architecture" in
  native) ;;
  universal) args+=(--arch arm64 --arch x86_64) ;;
  *) echo "Architecture must be native or universal" >&2; exit 1 ;;
esac
swift build "${args[@]}"
binary_dir="$(swift build "${args[@]}" --show-bin-path)"
app="build/Couleur.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/Couleur" "$app/Contents/MacOS/Couleur"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Assets.car "$app/Contents/Resources/"
ditto Resources/Fonts "$app/Contents/Resources/Fonts"
sparkle=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
if [[ "$architecture" == universal ]]; then
  for arch in arm64 x86_64; do lipo "$app/Contents/MacOS/Couleur" -verify_arch "$arch"; done
fi
if [[ "${COULEUR_DISTRIBUTION:-0}" == 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Add :CouleurUpdatesEnabled bool true' "$app/Contents/Info.plist"
fi
bash scripts/sign.sh "$app" com.aymeric.couleur
echo "Built $PWD/$app"
