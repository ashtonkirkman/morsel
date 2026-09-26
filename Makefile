# Morsel developer shortcuts. Everything Xcode-related needs a Mac; `icon`, `lint` and `proxy` work anywhere.
#
#   make generate   XcodeGen -> Morsel.xcodeproj
#   make build      Debug build for the newest iPhone simulator (same flags as CI)
#   make test       Build + run MorselTests on the simulator (same flags as CI)
#   make icon       Regenerate Morsel/Resources/.../AppIcon-1024.png
#   make lint       SwiftLint (native binary if installed, otherwise docker)
#   make proxy      Typecheck server/claude-proxy
#   make clean      Remove generated project + build products

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT      := Morsel.xcodeproj
SCHEME       := Morsel
RESULT       := TestResults.xcresult
SIM_UDID     ?= $(shell xcrun simctl list devices available -j 2>/dev/null | python3 scripts/pick_simulator.py 2>/dev/null)
DESTINATION  := platform=iOS Simulator,id=$(SIM_UDID)
XCB_FLAGS    := -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" \
                -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
# Pipe through xcpretty when present, fall back to raw output.
PRETTY       := $(shell command -v xcpretty >/dev/null 2>&1 && echo "| xcpretty --color --simple" || echo "")

.PHONY: help generate build test icon lint proxy clean

help:
	@grep -E '^#   make' Makefile | sed 's/^#   //'

generate:
	xcodegen generate --spec project.yml

build: generate
	@test -n "$(SIM_UDID)" || { echo "No iPhone simulator found (is Xcode installed?)"; exit 1; }
	set -o pipefail; xcodebuild $(XCB_FLAGS) build $(PRETTY)

test: generate
	@test -n "$(SIM_UDID)" || { echo "No iPhone simulator found (is Xcode installed?)"; exit 1; }
	rm -rf $(RESULT)
	set -o pipefail; xcodebuild $(XCB_FLAGS) -resultBundlePath $(RESULT) build test $(PRETTY)

icon:
	python3 scripts/make_icon.py

lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --reporter xcode; \
	else \
		docker run --rm -v "$$PWD":/work -w /work ghcr.io/realm/swiftlint:latest swiftlint lint --reporter xcode; \
	fi

proxy:
	@if [ -f server/claude-proxy/package.json ]; then \
		cd server/claude-proxy && ( [ -f package-lock.json ] && npm ci || npm install ) && npx tsc --noEmit; \
	else echo "server/claude-proxy not present yet"; fi

clean:
	rm -rf $(PROJECT) $(RESULT) build DerivedData
