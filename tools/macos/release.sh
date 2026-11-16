#!/bin/sh
# Export, sign (Developer ID, hardened runtime), notarize, staple and zip the macOS build.
#
#   tools/macos/release.sh            sign only, no notarization (prints what is missing)
#   NOTARY_PROFILE=name tools/macos/release.sh
#   NOTARY_KEY=/path/AuthKey_X.p8 NOTARY_KEY_ID=X NOTARY_ISSUER=uuid tools/macos/release.sh
#
# SIGN_IDENTITY (a certificate's SHA-1 or name) defaults to the one "Developer ID Application"
# identity in the login keychain. No identity or credential is stored in this repo.
# Needs the Godot 4.7.2 macOS export template installed (README, "Export").
set -e
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
OUT=build/macos
APP="$OUT/Hollow Hours.app"
ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | awk '{print $2}')}"
[ -n "$ID" ] || { echo "no Developer ID Application identity in the keychain"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
godot --headless --path . --export-release "macOS" "$OUT/export.zip"
ditto -x -k "$OUT/export.zip" "$OUT"
rm "$OUT/export.zip"
[ -d "$APP" ] || { echo "export produced no app"; exit 1; }

# Sign inside out (never --deep): the executable, then the bundle, with the secure timestamp.
codesign --force --timestamp --options runtime --entitlements tools/macos/HollowHours.entitlements -s "$ID" "$APP/Contents/MacOS/Hollow Hours"
codesign --force --timestamp --options runtime --entitlements tools/macos/HollowHours.entitlements -s "$ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ -n "$NOTARY_KEY" ]; then
  AUTH="--key $NOTARY_KEY --key-id $NOTARY_KEY_ID --issuer $NOTARY_ISSUER"
elif [ -n "$NOTARY_PROFILE" ]; then
  AUTH="--keychain-profile $NOTARY_PROFILE"
else
  echo "signed, NOT notarized: set NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER"
  exit 0
fi
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
# shellcheck disable=SC2086
xcrun notarytool submit "$OUT/notarize.zip" $AUTH --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"
rm "$OUT/notarize.zip"
ditto -c -k --keepParent "$APP" "$OUT/HollowHours-mac.zip"
ls -la "$OUT/HollowHours-mac.zip"
