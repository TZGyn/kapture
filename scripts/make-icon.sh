#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swift scripts/gen-icon.swift "$TMP/icon-1024.png"

mkdir -p "$TMP/Icon.iconset"
for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$s" "$s" "$TMP/icon-1024.png" --out "$TMP/Icon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z "$d" "$d" "$TMP/icon-1024.png" --out "$TMP/Icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$TMP/Icon.iconset" -o "$TMP/Icon.icns"
mkdir -p Kapture.app/Contents/Resources
cp "$TMP/Icon.icns" Kapture.app/Contents/Resources/Icon.icns
echo "Generated Kapture.app/Contents/Resources/Icon.icns"
