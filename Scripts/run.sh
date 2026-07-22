#!/usr/bin/env bash
# Convenience wrapper: build (debug) and launch Tydly in the menu bar.
# Equivalent to `make run`. Ctrl-C in this terminal quits the app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec swift run Tydly
