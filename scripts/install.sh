#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
destination="${1:-/Applications}/Couleur.app"
if pgrep -x Couleur >/dev/null; then
  echo "Quit Couleur before installing an update." >&2
  exit 1
fi
if [[ -e "$destination" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist")"
  if [[ "$identifier" != com.aymeric.couleur ]]; then
    echo "Refusing to replace a different app at $destination" >&2
    exit 1
  fi
fi
ditto build/Couleur.app "$destination"
open "$destination"
echo "Installed $destination"
