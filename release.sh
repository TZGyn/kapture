#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <version>    e.g. ./release.sh 1.0.1" >&2
    exit 1
fi
VERSION="$1"

# Notarization credentials. Configure once, e.g. in ~/.zshrc:
#   export KAPTURE_NOTARY_ASC_PROVIDER="<TeamID>"
#   export KAPTURE_NOTARY_API_KEY_PATH="$HOME/.config/kapture/AuthKey_XXXX.p8"
#   export KAPTURE_NOTARY_API_KEY_ID="<KeyID>"
#   export KAPTURE_NOTARY_API_ISSUER="<IssuerID>"
# If these are unset (or KAPTURE_SKIP_NOTARY=1), release.sh builds, zips, and stops
# there — the zip is signed with the Developer ID identity but NOT notarized.

./build-app.sh

mkdir -p dist
rm -f dist/Kapture.zip
ditto -c -k --keepParent Kapture.app dist/Kapture.zip

if [ -n "${KAPTURE_SKIP_NOTARY:-}" ]; then
    echo
    echo "Skipping notarization (KAPTURE_SKIP_NOTARY set)."
    shasum -a 256 dist/Kapture.zip
    echo
    echo "Tag and release with:"
    echo "  git tag v$VERSION && git push origin v$VERSION"
    echo "Attach dist/Kapture.zip to the GitHub release manually."
    exit 0
fi

REQUIRED_VARS="KAPTURE_NOTARY_ASC_PROVIDER KAPTURE_NOTARY_API_KEY_PATH KAPTURE_NOTARY_API_KEY_ID KAPTURE_NOTARY_API_ISSUER"
MISSING=""
for v in $REQUIRED_VARS; do
    if [ -z "${!v:-}" ]; then
        MISSING="$MISSING $v"
    fi
done
if [ -n "$MISSING" ]; then
    echo "Notarization skipped — missing env var(s):$MISSING (see header comments)." >&2
    shasum -a 256 dist/Kapture.zip
    echo
    echo "The zip above is signed but NOT notarized; Gatekeeper will warn users until it is."
    echo "Set the KAPTURE_NOTARY_* variables and re-run ./release.sh $VERSION."
    exit 0
fi

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find notarytool >/dev/null 2>&1; then
    echo "Notarization skipped — xcrun notarytool not found (requires Xcode 13+)." >&2
    shasum -a 256 dist/Kapture.zip
    exit 0
fi

echo "Submitting to Apple for notarization (first run can take minutes)..."
xcrun notarytool submit dist/Kapture.zip \
    --key "$KAPTURE_NOTARY_API_KEY_PATH" \
    --key-id "$KAPTURE_NOTARY_API_KEY_ID" \
    --issuer "$KAPTURE_NOTARY_API_ISSUER" \
    --wait \
    --output-format json > notary-result.json

STATUS=$(jq -r '.status' notary-result.json 2>/dev/null || echo "unknown")
if [ "$STATUS" != "Accepted" ]; then
    echo "Notarization failed with status: $STATUS" >&2
    if [ -f notary-result.json ]; then
        cat notary-result.json >&2
        rm -f notary-result.json
    fi
    exit 1
fi
rm -f notary-result.json

echo "Notarization accepted — stapling ticket onto the app..."
xcrun stapler staple Kapture.app
xcrun stapler validate Kapture.app

rm -f dist/Kapture.zip
ditto -c -k --keepParent Kapture.app dist/Kapture.zip

echo
echo "Done — notarized."
shasum -a 256 dist/Kapture.zip
echo
echo "Tag and release with:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "Attach dist/Kapture.zip to the GitHub release manually; the Homebrew cask is ready."
