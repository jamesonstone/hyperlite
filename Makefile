.DEFAULT_GOAL := help

.PHONY: help build test test-race vet fmt fmt-check install scan scan-json macos-build macos-test stop-hyper hyper run

HYPERLITE_APP ?= $(CURDIR)/build/Hyperlite.app
SWIFT_SOURCES := $(sort $(wildcard macos/Hyperlite/*.swift))
SWIFT_MODEL_TEST_SOURCES := macos/Hyperlite/HyperliteModels.swift macos/Hyperlite/HyperliteProjectModels.swift macos/Hyperlite/HyperlitePullRequestModels.swift macos/Hyperlite/HyperlitePullRequestPanel.swift macos/Hyperlite/HyperliteRateLimit.swift macos/Hyperlite/HyperliteRateLimitIndicator.swift macos/Hyperlite/HyperliteRateLimitPopover.swift macos/Hyperlite/HyperlitePresentation.swift macos/Hyperlite/HyperliteInteractionModels.swift macos/Hyperlite/HyperlitePalettePresentation.swift macos/Hyperlite/HyperliteTheme.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteProcess.swift macos/Hyperlite/HyperliteProcessSupport.swift macos/Hyperlite/HyperliteNotepadModels.swift macos/Hyperlite/HyperliteNoteSearchIndex.swift macos/Hyperlite/HyperliteNotepadState.swift macos/Hyperlite/HyperliteNotepadPersistence.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteTypography.swift macos/HyperliteTests/HyperliteInteractionModelTests.swift macos/HyperliteTests/HyperliteProjectIndexTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperlitePaletteTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperliteNotepadTests.swift macos/HyperliteTests/HyperliteNotepadRecoveryTests.swift macos/HyperliteTests/HyperlitePullRequestTests.swift macos/HyperliteTests/HyperliteRateLimitTests.swift macos/HyperliteTests/HyperliteTypographyTests.swift macos/HyperliteTests/HyperliteWorkspaceSizingTests.swift
SWIFT_MODEL_TEST_BINARY := build/tests/HyperliteInteractionModelTests

help:
	@printf '%s\n' 'Hyperlite developer workflow'
	@printf '%s\n' ''
	@printf '%s\n' '  make hyper       Build, replace, and open Hyperlite.app'
	@printf '%s\n' '  make test        Run Go tests'
	@printf '%s\n' '  make macos-test  Type-check the native app'

build:
	go build -o bin/hyperlite ./cmd/hyperlite

test:
	go test ./...

test-race:
	go test -race ./...

vet:
	go vet ./...

fmt:
	gofmt -w cmd internal

fmt-check:
	test -z "$$(gofmt -l cmd internal)"

install:
	go install ./cmd/hyperlite

scan:
	go run ./cmd/hyperlite

scan-json:
	go run ./cmd/hyperlite --json

macos-build:
	HYPERLITE_APP="$(HYPERLITE_APP)" ./scripts/build-macos-app.sh

macos-test:
	xcrun swiftc -parse-as-library -typecheck -framework SwiftUI -framework AppKit -framework Carbon -framework NaturalLanguage $(SWIFT_SOURCES)
	mkdir -p "$(dir $(SWIFT_MODEL_TEST_BINARY))"
	xcrun swiftc -parse-as-library -framework SwiftUI -framework AppKit -framework NaturalLanguage $(SWIFT_MODEL_TEST_SOURCES) -o "$(SWIFT_MODEL_TEST_BINARY)"
	"$(SWIFT_MODEL_TEST_BINARY)"

stop-hyper:
	@osascript -e 'tell application id "com.jamesonstone.hyperlite" to quit' >/dev/null 2>&1 || true
	@pids="$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite" { print $$1 }')"; \
	if [ -n "$$pids" ]; then \
		kill -TERM $$pids 2>/dev/null || true; \
		attempt=0; \
		while [ -n "$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite" { print $$1 }')" ] && [ "$$attempt" -lt 50 ]; do \
			sleep 0.1; \
			attempt=$$((attempt + 1)); \
		done; \
		if [ -n "$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite" { print $$1 }')" ]; then \
			echo "Hyperlite is still running; refusing to replace it." >&2; \
			exit 1; \
		fi; \
	fi

hyper: stop-hyper
	@$(MAKE) macos-build
	open -n "$(HYPERLITE_APP)"

run: hyper
