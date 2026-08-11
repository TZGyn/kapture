#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <version>    e.g. ./release.sh 1.0.1" >&2
    exit 1
fi
VERSION="$1"

./build-app.sh

mkdir -p dist
rm -f dist/Kapture.zip
ditto -c -k --keepParent Kapture.app dist/Kapture.zip
shasum -a 256 dist/Kapture.zip

echo
echo "Tag and release with:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "Attach dist/Kapture.zip to the GitHub release manually."
