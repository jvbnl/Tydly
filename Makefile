# Tydly — command-line workflow (no Xcode required).
#
#   make run     Build (debug) and launch Tydly in the menu bar via `swift run`.
#   make build   Release build of the executable.
#   make app     Assemble a distributable Tydly.app (menu-bar agent) into dist/.
#   make open    Build the .app and launch it.
#   make test    Run the TydlyCore unit tests (the ten product rules).
#   make audit   Verify signing, sandbox, and no-network invariants.
#   make clean    Remove build artifacts.
#
# Requires the macOS SDK (Xcode.app or the Command Line Tools). You never open Xcode.

.PHONY: run build app open test audit clean

run:
	swift build
	CONFIGURATION=debug ./Scripts/build_app.sh
	./dist/Tydly.app/Contents/MacOS/Tydly

build:
	swift build -c release

app: build
	./Scripts/build_app.sh

open: app
	open dist/Tydly.app

test:
	swift test

audit: app
	./Scripts/audit_privacy.sh

clean:
	swift package clean
	rm -rf .build dist
