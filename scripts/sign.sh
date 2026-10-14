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
codesign --force --sign "${identity:--}" --timestamp=none --identifier "$bundle_id" "$app"
if [[ -z "$identity" || "$identity" == - ]]; then
  echo 'Ad-hoc signed: Screen Recording permission may need renewing after a rebuild.'
fi
