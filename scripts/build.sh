#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
  echo "Usage: scripts/build.sh [release|debug]" >&2
  exit 1
fi
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="build/Couleur.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Couleur" "$app/Contents/MacOS/Couleur"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Assets.car "$app/Contents/Resources/"
bash scripts/sign.sh "$app" com.aymeric.couleur
echo "Built $PWD/$app"
