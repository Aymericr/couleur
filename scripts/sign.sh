#!/bin/bash
# A certificate-backed identity lets macOS retain privacy permissions across builds.
# CI and machines without a signing certificate can still build with ad-hoc signing.
set -euo pipefail
app="$1"
bundle_id="$2"
identity="${COULEUR_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$(printf '%s\n' "$identities" | awk '/Developer ID Application:/ {print $2; exit}')"
  if [[ -z "$identity" ]]; then
    identity="$(printf '%s\n' "$identities" | awk '/Apple Development:/ {print $2; exit}')"
  fi
fi
options=(--force --sign "${identity:--}")
if [[ "${COULEUR_DISTRIBUTION:-0}" == 1 ]]; then
  if ! security find-identity -v -p codesigning | awk '/Developer ID Application:/ {print}' | grep -Fq -- "$identity" || [[ -z "$identity" ]]; then
    echo 'Distribution requires a Developer ID Application identity.' >&2; exit 1
  fi
  options+=(--options runtime --timestamp)
else
  options+=(--timestamp=none)
fi
framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$framework" ]]; then
  # Sign nested code inside-out. Preserve Sparkle's own hardened-runtime entitlements.
  for nested in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign "${options[@]}" --preserve-metadata=entitlements "$framework/Versions/B/$nested"
  done
  codesign "${options[@]}" "$framework"
fi
codesign "${options[@]}" --entitlements "$(dirname "$0")/../Resources/Release.entitlements" --identifier "$bundle_id" "$app"
codesign --verify --deep --strict "$app"
if [[ -z "$identity" || "$identity" == - ]]; then
  echo 'Ad-hoc signed: Screen Recording permission may need renewing after a rebuild.'
fi
