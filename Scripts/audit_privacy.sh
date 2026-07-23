#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/Tydly.app}"
DECLARED_ENTITLEMENTS="$ROOT/Sources/Tydly/Tydly.entitlements"

if [[ ! -d "$APP" ]]; then
	echo "error: app bundle not found at $APP" >&2
	exit 1
fi

require_true() {
	local key="$1"
	local plist="$2"
	local value
	value="$(plutil -extract "$key" raw -o - "$plist")"
	if [[ "$value" != "true" ]]; then
		echo "error: expected $key=true in $plist" >&2
		exit 1
	fi
}

reject_key() {
	local key="$1"
	local plist="$2"
	if plutil -extract "$key" raw -o - "$plist" >/dev/null 2>&1; then
		echo "error: forbidden entitlement $key found in $plist" >&2
		exit 1
	fi
}

require_true "com.apple.security.app-sandbox" "$DECLARED_ENTITLEMENTS"
require_true "com.apple.security.files.user-selected.read-write" "$DECLARED_ENTITLEMENTS"
reject_key "com.apple.security.network.client" "$DECLARED_ENTITLEMENTS"
reject_key "com.apple.security.network.server" "$DECLARED_ENTITLEMENTS"

FORBIDDEN_SOURCE_PATTERN='(^|[^[:alnum:]_])(import[[:space:]]+(Network|UserNotifications)|URLSession|NSURLConnection|NWConnection|PrivateCloudComputeLanguageModel|NSUserNotification|UNUserNotificationCenter)'
if /usr/bin/grep -R -n -E \
	--include='*.swift' \
	"$FORBIDDEN_SOURCE_PATTERN" \
	"$ROOT/Sources"; then
	echo "error: forbidden network or notification API found" >&2
	exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

RUNTIME_ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$RUNTIME_ENTITLEMENTS"' EXIT
codesign -d --entitlements :- "$APP" >"$RUNTIME_ENTITLEMENTS" 2>/dev/null

require_true "com.apple.security.app-sandbox" "$RUNTIME_ENTITLEMENTS"
require_true "com.apple.security.files.user-selected.read-write" "$RUNTIME_ENTITLEMENTS"
reject_key "com.apple.security.network.client" "$RUNTIME_ENTITLEMENTS"
reject_key "com.apple.security.network.server" "$RUNTIME_ENTITLEMENTS"

MINIMUM_SYSTEM_VERSION="$(
	plutil -extract LSMinimumSystemVersion raw -o - "$APP/Contents/Info.plist"
)"
if [[ "$MINIMUM_SYSTEM_VERSION" != "26.0" ]]; then
	echo "error: expected LSMinimumSystemVersion=26.0, got $MINIMUM_SYSTEM_VERSION" >&2
	exit 1
fi

echo "Privacy audit passed for $APP"
