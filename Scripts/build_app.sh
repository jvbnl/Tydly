#!/usr/bin/env bash
#
# Assemble a proper Tydly.app bundle from the SwiftPM release build — no Xcode.
# Run `swift build -c release` first (the Makefile's `app` target does this for you).
#
# Every assembled app is signed so sandbox and keychain boundaries are exercised locally.

set -euo pipefail

APP_NAME="Tydly"
BUNDLE_ID="io.gymly.tydly"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
BIN_DIR="$(cd "$ROOT" && swift build -c "$CONFIGURATION" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
PLIST="$ROOT/Sources/Tydly/Info.plist"
ENTITLEMENTS="$ROOT/Sources/Tydly/Tydly.entitlements"
OUT="$ROOT/dist/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_IDENTIFIER_PREFIX="${APP_IDENTIFIER_PREFIX:-}"

if [[ "$SIGN_IDENTITY" != "-" && -z "$APP_IDENTIFIER_PREFIX" ]]; then
	echo "error: APP_IDENTIFIER_PREFIX is required for non-ad-hoc signing" >&2
	exit 1
fi

if [[ ! -x "$BIN" ]]; then
	echo "error: $CONFIGURATION binary not found at $BIN" >&2
	echo "       build that configuration before assembling the app." >&2
	exit 1
fi

echo "Assembling $APP_NAME.app ($CONFIGURATION)…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
mkdir -p "$OUT/Contents/Resources"
mkdir -p "$OUT/Contents/Frameworks"

cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"
cp "$PLIST" "$OUT/Contents/Info.plist"

# Copy the SwiftPM-generated resource bundle (localizations etc.).
BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ ! -d "$BUNDLE" ]]; then
	echo "error: resource bundle not found at $BUNDLE" >&2
	exit 1
fi
cp -R "$BUNDLE" "$OUT/Contents/Resources/"

SQLCIPHER_FRAMEWORK="$BIN_DIR/SQLCipher.framework"
if [[ ! -d "$SQLCIPHER_FRAMEWORK" ]]; then
	echo "error: SQLCipher framework not found at $SQLCIPHER_FRAMEWORK" >&2
	exit 1
fi
cp -R "$SQLCIPHER_FRAMEWORK" "$OUT/Contents/Frameworks/"

EXPANDED_ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$EXPANDED_ENTITLEMENTS"' EXIT
cp "$ENTITLEMENTS" "$EXPANDED_ENTITLEMENTS"
/usr/libexec/PlistBuddy \
	-c "Set :com.apple.application-identifier ${APP_IDENTIFIER_PREFIX}${BUNDLE_ID}" \
	"$EXPANDED_ENTITLEMENTS"

# Always sign assembled development apps so local tests exercise App Sandbox and the
# production entitlement boundary. The default "-" identity is ad-hoc and never leaves the
# machine. Release automation supplies a stable Developer ID or App Store identity.
SIGN_ARGS=(
	--force
	--options runtime
	--sign "$SIGN_IDENTITY"
)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
	SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$OUT/Contents/Frameworks/SQLCipher.framework"
codesign \
	"${SIGN_ARGS[@]}" \
	--entitlements "$EXPANDED_ENTITLEMENTS" \
	"$OUT"

echo "Built and signed $OUT"
