#!/usr/bin/env bash
#
# Assemble a proper Tydly.app bundle from the SwiftPM release build — no Xcode.
# Run `swift build -c release` first (the Makefile's `app` target does this for you).
#
# Optional code signing (App Sandbox + the no-network entitlement) is included but
# commented out; fill in your signing identity to enable it.

set -euo pipefail

APP_NAME="Tydly"
BUNDLE_ID="io.gymly.tydly"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.build/release/$APP_NAME"
PLIST="$ROOT/Sources/Tydly/Info.plist"
ENTITLEMENTS="$ROOT/Sources/Tydly/Tydly.entitlements"
OUT="$ROOT/dist/$APP_NAME.app"

if [[ ! -x "$BIN" ]]; then
	echo "error: release binary not found at $BIN" >&2
	echo "       run 'swift build -c release' (or 'make app') first." >&2
	exit 1
fi

echo "Assembling $APP_NAME.app…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
mkdir -p "$OUT/Contents/Resources"

cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"
cp "$PLIST" "$OUT/Contents/Info.plist"

# Copy the SwiftPM-generated resource bundle (localizations etc.), if present.
BUNDLE="$ROOT/.build/release/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$BUNDLE" ]]; then
	cp -R "$BUNDLE" "$OUT/Contents/Resources/"
fi

# --- Code signing (optional) -------------------------------------------------
# Signing with the entitlements is what actually enforces the sandbox + the
# absent network entitlement. Uncomment and set SIGN_ID to enable.
#
# SIGN_ID="Developer ID Application: Your Name (TEAMID)"
# codesign --force --options runtime \
#     --entitlements "$ENTITLEMENTS" \
#     --sign "$SIGN_ID" \
#     "$OUT"
# -----------------------------------------------------------------------------

echo "Built $OUT"
