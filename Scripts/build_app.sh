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
BIN_DIR="$(cd "$ROOT" && swift build -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
PLIST="$ROOT/Sources/Tydly/Info.plist"
ENTITLEMENTS="$ROOT/Sources/Tydly/Tydly.entitlements"
OUT="$ROOT/dist/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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

# Copy the SwiftPM-generated resource bundle (localizations etc.).
BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ ! -d "$BUNDLE" ]]; then
	echo "error: resource bundle not found at $BUNDLE" >&2
	exit 1
fi
cp -R "$BUNDLE" "$OUT/Contents/Resources/"

# Always sign assembled development apps so local tests exercise App Sandbox and the
# production entitlement boundary. The default "-" identity is ad-hoc and never leaves the
# machine. Release automation supplies a stable Developer ID or App Store identity.
SIGN_ARGS=(
	--force
	--options runtime
	--entitlements "$ENTITLEMENTS"
	--sign "$SIGN_IDENTITY"
)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
	SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$OUT"

echo "Built and signed $OUT"
