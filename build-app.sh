#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

BIN=".build/release/Kapture"
APP="Kapture.app"
CERT="kapture-dev"
SIGN_DIR="$HOME/.config/kapture"
KEYCHAIN="$SIGN_DIR/signing.keychain-db"
KCHAIN_PASS="kapture-dev"
mkdir -p "$SIGN_DIR"

# Prefer a Developer ID Application identity (login keychain) so the app gets
# clean Gatekeeper behavior; fall back to the self-signed "kapture-dev" identity.
# Resolve by keychain path to avoid ambiguous matches.
DEV_IDENT=""
if command -v security >/dev/null 2>&1; then
    DEV_IDENT=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application:/ { print $2; exit }')
fi
SIGN_KEYCHAIN=""
if [ -n "$DEV_IDENT" ]; then
    CERT="$DEV_IDENT"
    echo "Using Developer ID identity: $CERT"
    # Ensure the login keychain holding the Dev ID is unlocked & accessible.
    security unlock-keychain "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
    SIGN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
else
    CERT="kapture-dev"
    echo "Using self-signed identity 'kapture-dev'"
    SIGN_KEYCHAIN="$KEYCHAIN"
fi
DEV_IDENT="${DEV_IDENT:-}"  # ensure set for later use

if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KCHAIN_PASS" "$KEYCHAIN" 2>/dev/null
    security set-keychain-settings -lut 86400 "$KEYCHAIN"
fi
security unlock-keychain -p "$KCHAIN_PASS" "$KEYCHAIN" 2>/dev/null || true

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "kapture-dev"; then
    echo "Creating self-signed code signing identity '$CERT' (one-time)..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = kapture-dev

[ v3 ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
CNF

    BREW_OPENSSL=""
    if [ -x /opt/homebrew/bin/openssl ]; then
        BREW_OPENSSL=/opt/homebrew/bin/openssl
    elif [ -x /usr/local/bin/openssl ]; then
        BREW_OPENSSL=/usr/local/bin/openssl
    fi

    if [ -n "$BREW_OPENSSL" ]; then
        "$BREW_OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
            -config "$TMP/cert.cnf" 2>/dev/null
        "$BREW_OPENSSL" pkcs12 -export -legacy \
            -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
            -out "$TMP/cert.p12" -passout pass:kapture 2>/dev/null
        security import "$TMP/cert.p12" -k "$KEYCHAIN" \
            -P kapture -T /usr/bin/codesign 2>/dev/null
    else
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
            -config "$TMP/cert.cnf" 2>/dev/null
        openssl x509 -in "$TMP/cert.pem" -outform der -out "$TMP/cert.der" 2>/dev/null
        openssl pkcs8 -topk8 -nocrypt -in "$TMP/key.pem" -outform der -out "$TMP/key.der" 2>/dev/null
        security add-certificates -k "$KEYCHAIN" "$TMP/cert.der" 2>/dev/null
        security import "$TMP/key.der" -k "$KEYCHAIN" -T /usr/bin/codesign 2>/dev/null
    fi
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Kapture"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Kapture</string>
    <key>CFBundleIdentifier</key>
    <string>dev.tzgyn.kapture</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Kapture</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Icon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>10</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x scripts/make-icon.sh
./scripts/make-icon.sh

if [ -n "$SIGN_KEYCHAIN" ]; then
    codesign --force --options runtime --sign "$CERT" --keychain "$SIGN_KEYCHAIN" "$APP"
else
    codesign --force --sign "$CERT" "$APP"
fi

if [ -n "$DEV_IDENT" ]; then
    echo "Built $APP (signed with Developer ID '$CERT') — drag to /Applications or run: open $APP"
else
    echo "Built $APP (signed with stable identity '$CERT') — drag to /Applications or run: open $APP"
fi
