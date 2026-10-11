#!/bin/bash
# Builds build/Swide.app. With "install": copies it to ~/Applications and (re)launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Swide.app"
IDENTITY_NAME="Swide Local Signing"

cd "$ROOT"
swift build -c release --product Swide

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Swide "$APP/Contents/MacOS/Swide"
cp Resources/Info.plist "$APP/Contents/Info.plist"
scripts/package-bridge.sh "$APP/Contents/Resources/swide-bridge.vsix"

# A stable identity keeps the Accessibility grant across rebuilds; ad hoc resets it.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    codesign --force --sign "$IDENTITY_NAME" "$APP"
else
    echo "Note: '$IDENTITY_NAME' not found, signing ad hoc (run scripts/create-signing-cert.sh once)."
    codesign --force --sign - "$APP"
fi
echo "Built: $APP"

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/Swide.app"
    pkill -x Swide 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    open "$DEST"
    echo "Installed and launched: $DEST"
fi
