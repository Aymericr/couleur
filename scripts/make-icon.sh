#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Xcode 26 or later compiles the Icon Composer source for current macOS,
# along with an ICNS fallback for older systems. Normal builds use the
# checked-in results and do not need Icon Composer or asset compilation.
output="$(mktemp -d "${TMPDIR:-/tmp}/couleur-icon.XXXXXX")"
trap 'rm -rf "$output"' EXIT

xcrun actool Resources/AppIcon.icon \
  --compile "$output" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$output/Info.plist" \
  --output-format human-readable-text

cp "$output/AppIcon.icns" Resources/AppIcon.icns
cp "$output/Assets.car" Resources/Assets.car
echo "Updated Resources/AppIcon.icns and Resources/Assets.car"
