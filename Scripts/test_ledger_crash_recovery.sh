#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$(cd "$ROOT" && swift build -c debug --show-bin-path)"
PROBE="$BIN_DIR/TydlyLedgerCrashProbe"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

if [[ ! -x "$PROBE" ]]; then
	echo "error: ledger crash probe not built at $PROBE" >&2
	exit 1
fi

expect_crash_boundary() {
	local mode="$1"
	local directory="$2"

	mkdir -m 700 "$directory"
	set +e
	"$PROBE" "$mode" "$directory"
	local status=$?
	set -e
	if [[ "$status" -ne 86 ]]; then
		echo "error: $mode exited $status instead of the injected crash boundary" >&2
		exit 1
	fi
}

PREPARED="$FIXTURE_ROOT/prepared"
expect_crash_boundary "prepare-and-crash" "$PREPARED"
"$PROBE" "verify-prepared" "$PREPARED"

APPLIED="$FIXTURE_ROOT/applied"
expect_crash_boundary "apply-and-crash" "$APPLIED"
"$PROBE" "verify-applied" "$APPLIED"

echo "Ledger crash-recovery probes passed"
