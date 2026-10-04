.DEFAULT_GOAL := help

.PHONY: help build test test-race vet fmt fmt-check install macos-build macos-test stop-hyper hyper run

HYPERLITE_APP ?= $(CURDIR)/build/Hyperlite.app
SWIFT_SOURCES := $(sort $(wildcard macos/Hyperlite/*.swift))
SWIFT_MODEL_TEST_SOURCES := macos/Hyperlite/HyperliteModels.swift macos/Hyperlite/HyperliteProjectModels.swift macos/Hyperlite/HyperlitePullRequestModels.swift macos/Hyperlite/HyperlitePullRequestPanel.swift macos/Hyperlite/HyperlitePullRequestRows.swift macos/Hyperlite/HyperlitePullRequestHover.swift macos/Hyperlite/HyperliteRateLimit.swift macos/Hyperlite/HyperliteRateLimitModels.swift macos/Hyperlite/HyperliteRateLimitIndicator.swift macos/Hyperlite/HyperliteRateLimitPopover.swift macos/Hyperlite/HyperlitePresentation.swift macos/Hyperlite/HyperliteInteractionModels.swift macos/Hyperlite/HyperliteInteractionEntries.swift macos/Hyperlite/HyperlitePalettePresentation.swift macos/Hyperlite/HyperliteTheme.swift macos/Hyperlite/HyperliteThemeCatalog.swift macos/Hyperlite/HyperliteThemePalettesDark.swift macos/Hyperlite/HyperliteThemePalettesLight.swift macos/Hyperlite/HyperliteAppearance.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteDashboardListState.swift macos/Hyperlite/HyperliteDashboardListControls.swift macos/Hyperlite/HyperlitePullRequestReviewMarkers.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteProcess.swift macos/Hyperlite/HyperliteProcessSupport.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteTypography.swift macos/HyperliteTests/HyperliteInteractionModelTests.swift macos/HyperliteTests/HyperliteProjectIndexTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperlitePaletteTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperlitePullRequestTests.swift macos/HyperliteTests/HyperliteRateLimitTests.swift macos/HyperliteTests/HyperliteTypographyTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperliteOpenPRControlsTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteOpenPRMergePrompt.swift macos/HyperliteTests/HyperliteOpenPRMergePromptTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteOpenPRTitleCluster.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperlitePullRequestReviewMarkerTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperliteAppearanceTests.swift macos/HyperliteTests/HyperlitePullRequestHoverTests.swift macos/Hyperlite/HyperlitePullRequestRowContent.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperlitePullRequestRowLayout.swift macos/Hyperlite/HyperliteWorkflowActivityModels.swift macos/Hyperlite/HyperlitePullRequestSections.swift macos/Hyperlite/HyperliteWorkflowStripPresentation.swift macos/Hyperlite/HyperliteRunningWorkflowChip.swift macos/Hyperlite/HyperliteWorkflowStrip.swift macos/Hyperlite/HyperliteWorkflowHoverCard.swift macos/Hyperlite/HyperliteProjectSectionHeader.swift macos/Hyperlite/HyperliteActivityPollSchedule.swift macos/Hyperlite/HyperliteAmbientRefreshSchedule.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperliteAmbientRefreshScheduleTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/HyperliteTests/HyperliteWorkflowActivityTests.swift macos/HyperliteTests/HyperlitePullRequestSectionsTests.swift macos/HyperliteTests/HyperliteActivityPollScheduleTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteOpenPRProjectStage.swift macos/Hyperlite/HyperliteHiddenProjectList.swift macos/Hyperlite/HyperliteOpenPRWatchColumn.swift macos/Hyperlite/HyperlitePipelineAlert.swift macos/HyperliteTests/HyperliteOpenPRWatchStageTests.swift macos/HyperliteTests/HyperlitePipelineAlertTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteIssueReference.swift macos/HyperliteTests/HyperliteIssueReferenceTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteWorkspaceNavigation.swift macos/Hyperlite/HyperliteWorkspaceNavHighlight.swift macos/HyperliteTests/HyperliteWorkspaceNavigationTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteProjectIgnorePresentation.swift macos/HyperliteTests/HyperliteProjectIgnoreTests.swift
SWIFT_MODEL_TEST_SOURCES += macos/Hyperlite/HyperliteFailedPipelinePresentation.swift macos/HyperliteTests/HyperliteFailedPipelineTests.swift
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

macos-build:
	HYPERLITE_APP="$(HYPERLITE_APP)" ./scripts/build-macos-app.sh

macos-test:
	xcrun swiftc -parse-as-library -typecheck -framework SwiftUI -framework AppKit -framework Carbon $(SWIFT_SOURCES)
	mkdir -p "$(dir $(SWIFT_MODEL_TEST_BINARY))"
	xcrun swiftc -parse-as-library -framework SwiftUI -framework AppKit $(SWIFT_MODEL_TEST_SOURCES) -o "$(SWIFT_MODEL_TEST_BINARY)"
	"$(SWIFT_MODEL_TEST_BINARY)"

stop-hyper:
	@osascript -e 'tell application id "com.jamesonstone.hyperlite" to quit' >/dev/null 2>&1 || true
	@pids="$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite-cli" { print $$1 }')"; \
	if [ -n "$$pids" ]; then \
		kill -TERM $$pids 2>/dev/null || true; \
		attempt=0; \
		while [ -n "$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite-cli" { print $$1 }')" ] && [ "$$attempt" -lt 50 ]; do \
			sleep 0.1; \
			attempt=$$((attempt + 1)); \
		done; \
		if [ -n "$$(ps -axo pid=,comm= | awk '$$2 == "$(HYPERLITE_APP)/Contents/MacOS/Hyperlite" || $$2 == "$(HYPERLITE_APP)/Contents/MacOS/hyperlite-cli" { print $$1 }')" ]; then \
			echo "Hyperlite is still running; refusing to replace it." >&2; \
			exit 1; \
		fi; \
	fi

hyper: stop-hyper
	@$(MAKE) macos-build
	open -n "$(HYPERLITE_APP)"

run: hyper
