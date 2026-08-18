import Foundation

enum HyperliteAgentSessionPolicyTests {
    static func run() {
        testIntegrationOutcomes()
        testRouteResolution()
        testDismissalPolicy()
        testNotchVisibilityPolicy()
        testAttentionAccessibilityLabel()
        testSingleSubmissionAndStaleIdentity()
        testAnswerResetPolicy()
        testDuplicateSessionSelection()
        testLineBufferIsolation()
        testDiscoveryRefreshPolicy()
    }

    private static func testDiscoveryRefreshPolicy() {
        let last = Date(timeIntervalSince1970: 100)
        expect(!HyperliteAgentDiscoveryRefreshPolicy.shouldRefresh(
            lastRefresh: last,
            now: last.addingTimeInterval(59)
        ), "fresh foreground activation does not rediscover")
        expect(HyperliteAgentDiscoveryRefreshPolicy.shouldRefresh(
            lastRefresh: last,
            now: last.addingTimeInterval(60)
        ), "stale foreground activation rediscovers")
        expect(HyperliteAgentVerificationPolicy.timeoutSeconds == 10,
               "integration verification timeout stays bounded")
    }

    private static func testNotchVisibilityPolicy() {
        expect(!HyperliteAgentNotchVisibilityPolicy.showsChrome(
            hasPhysicalNotch: false, expanded: false, pointerInside: false
        ), "idle notchless chrome stays hidden")
        expect(HyperliteAgentNotchVisibilityPolicy.showsChrome(
            hasPhysicalNotch: false, expanded: false, pointerInside: true
        ), "hover reveals notchless chrome without expanding")
        expect(HyperliteAgentNotchVisibilityPolicy.showsChrome(
            hasPhysicalNotch: false, expanded: true, pointerInside: false
        ), "expanded notchless companion stays visible")
        expect(HyperliteAgentNotchVisibilityPolicy.showsChrome(
            hasPhysicalNotch: true, expanded: false, pointerInside: false
        ), "physical notch chrome remains visible")
        expect(!HyperliteAgentNotchVisibilityPolicy.showsShadow(
            hasPhysicalNotch: false, chromeVisible: false
        ), "hidden notchless chrome casts no shadow")
        expect(HyperliteAgentNotchVisibilityPolicy.showsShadow(
            hasPhysicalNotch: false, chromeVisible: true
        ), "revealed notchless chrome casts its native shadow")
        expect(!HyperliteAgentNotchVisibilityPolicy.showsShadow(
            hasPhysicalNotch: true, chromeVisible: true
        ), "physical notch chrome never adds a floating shadow")
    }

    private static func testAttentionAccessibilityLabel() {
        let pending = HyperliteAgentPendingAction(
            requestID: "request",
            kind: "approval",
            title: "Approve command",
            context: "git status",
            arguments: nil,
            completeContext: true,
            canAllowOnce: true,
            canDeny: true,
            canAnswer: false,
            canAllowSession: false,
            canRevoke: false
        )
        let active = session(action: pending)
        expect(active.phase == .processing && active.needsAttention,
               "fixture covers pending action during processing")
        let sharedLabel = HyperliteAgentAccessibilityPolicy.sessionLabel(active)
        expect(sharedLabel.contains("needs attention"),
               "shared workspace and notch row label states pending attention explicitly")
        expect(sharedLabel.contains(active.profile),
               "shared workspace and notch row label retains provider identity")
    }

    private static func testIntegrationOutcomes() {
        let partial = HyperliteAgentIntegrationOutcomePolicy.resolve(
            wasConsented: false,
            grantsConsentOnSuccess: true,
            successfulMutations: 1,
            failedMutations: 2,
            refreshSucceeded: false
        )
        expect(partial.shouldGrantConsent, "partial onboarding success grants consent")
        expect(!partial.shouldRestartService, "partial onboarding starts without restart")

        let allFailed = HyperliteAgentIntegrationOutcomePolicy.resolve(
            wasConsented: false,
            grantsConsentOnSuccess: true,
            successfulMutations: 0,
            failedMutations: 3,
            refreshSucceeded: true
        )
        expect(!allFailed.shouldGrantConsent, "all-failure onboarding retains consent gate")
        expect(!allFailed.shouldRestartService, "all-failure onboarding does not start service")

        let existingPartial = HyperliteAgentIntegrationOutcomePolicy.resolve(
            wasConsented: true,
            grantsConsentOnSuccess: false,
            successfulMutations: 1,
            failedMutations: 1,
            refreshSucceeded: false
        )
        expect(existingPartial.shouldRestartService, "existing service restarts after a mutation")
        let existingFailure = HyperliteAgentIntegrationOutcomePolicy.resolve(
            wasConsented: true,
            grantsConsentOnSuccess: false,
            successfulMutations: 0,
            failedMutations: 1,
            refreshSucceeded: true
        )
        expect(!existingFailure.shouldRestartService, "existing service does not restart after all failures")
    }

    private static func testRouteResolution() {
        let cursor = session(routing: routing(bundleID: "com.todesktop.230313mzl4w4u92"))
        expect(cursor.routeDestination?.label == "Open Cursor", "known bundle identifies app")

        let iTermHook = session(routing: routing(bundleID: "com.googlecode.iterm2"))
        expect(iTermHook.routeDestination?.label == "Open iTerm", "Claude hook names owning iTerm")

        let terminalCLI = session(routing: routing(terminal: "iTerm.app"))
        expect(terminalCLI.routeDestination?.label == "Open iTerm", "terminal metadata identifies route")
        expect(HyperliteAgentRoutePolicy.effectiveBundleID(terminalCLI.routing) == "com.googlecode.iterm2",
               "terminal route resolves launch bundle")

        let unknown = session(routing: routing(bundleID: "com.example.agent"))
        expect(unknown.routeDestination?.label == "Open Client", "unknown app does not claim a provider route")

        let finder = session(routing: routing(workspacePath: "/tmp/hyperlite"))
        expect(finder.routeDestination == .finder, "workspace-only route uses Finder")
        expect(finder.routeDestination?.label == "Reveal in Finder", "Finder label describes route")
    }

    private static func testDismissalPolicy() {
        expect(HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: true,
            hasAutomaticDelay: true,
            pointerInside: false,
            editing: false,
            companionFocused: false
        ), "idle automatic popup dismisses")
        expect(!HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: true,
            hasAutomaticDelay: true,
            pointerInside: false,
            editing: false,
            companionFocused: true
        ), "keyboard or VoiceOver focus pauses dismissal")
        expect(!HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: true,
            hasAutomaticDelay: true,
            pointerInside: true,
            editing: false,
            companionFocused: false
        ), "pointer interaction pauses dismissal")
        expect(!HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: true,
            hasAutomaticDelay: false,
            pointerInside: false,
            editing: false,
            companionFocused: false
        ), "manual expansion has no automatic dismissal")
        expect(!HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: false,
            hasAutomaticDelay: true,
            pointerInside: false,
            editing: false,
            companionFocused: false
        ), "collapsed companion does not schedule dismissal")
    }

    private static func testSingleSubmissionAndStaleIdentity() {
        let original = HyperliteAgentActionIdentity(sessionID: "claude:one", requestID: "request", revision: 1)
        let current = HyperliteAgentActionIdentity(sessionID: "claude:one", requestID: "request", revision: 2)
        var tracker = HyperliteAgentActionSubmissionTracker()
        expect(tracker.begin(original), "first exact submission begins")
        expect(!tracker.begin(original), "duplicate exact submission is rejected")
        tracker.retain([current])
        expect(!tracker.contains(original), "stale revision is removed")
        expect(tracker.begin(current), "current revision may submit")
        tracker.resolve(sessionID: current.sessionID, requestID: current.requestID)
        expect(!tracker.contains(current), "result resolves pending submission")
    }

    private static func testAnswerResetPolicy() {
        let original = HyperliteAgentActionIdentity(sessionID: "claude:one", requestID: "question", revision: 1)
        let revised = HyperliteAgentActionIdentity(sessionID: "claude:one", requestID: "question", revision: 2)
        let other = HyperliteAgentActionIdentity(sessionID: "claude:two", requestID: "question", revision: 1)
        expect(!HyperliteAgentAnswerResetPolicy.shouldReset(from: original, to: original),
               "same exact question preserves draft")
        expect(HyperliteAgentAnswerResetPolicy.shouldReset(from: original, to: revised),
               "new revision clears stale draft")
        expect(HyperliteAgentAnswerResetPolicy.shouldReset(from: original, to: other),
               "new session clears stale draft")
    }

    private static func testDuplicateSessionSelection() {
        let base = Date(timeIntervalSince1970: 10)
        let stale = session(revision: 1, title: "stale", updatedAt: base.addingTimeInterval(20))
        let revised = session(revision: 2, title: "revised", updatedAt: base)
        let selected = HyperliteAgentSessionSelection.newestByID([stale, revised])
        expect(selected[stale.id]?.title == "revised", "higher revision wins duplicate alert identity")

        let newer = session(revision: 2, title: "newer", updatedAt: base.addingTimeInterval(30))
        let tied = HyperliteAgentSessionSelection.newestByID([revised, newer])
        expect(tied[stale.id]?.title == "newer", "newer timestamp breaks duplicate revision tie")
    }

    private static func testLineBufferIsolation() {
        let first = HyperliteAgentLineBuffer()
        expect(first.append(Data("old".utf8)).isEmpty, "partial first launch is buffered")
        let second = HyperliteAgentLineBuffer()
        let secondLines = second.append(Data("new\n".utf8))
        expect(String(data: secondLines[0], encoding: .utf8) == "new", "new launch has isolated buffer")
        let firstLines = first.append(Data("-tail\n".utf8))
        expect(String(data: firstLines[0], encoding: .utf8) == "old-tail", "old buffer remains independent")

        let overflow = HyperliteAgentLineBuffer()
        expect(overflow.append(Data(repeating: 0x61, count: 2_097_153)).isEmpty,
               "oversized partial record is discarded")
        let fresh = overflow.append(Data("fresh\n".utf8))
        expect(fresh.count == 1 && String(data: fresh[0], encoding: .utf8) == "fresh",
               "fresh record is isolated from discarded oversized input")
    }

    private static func routing(
        bundleID: String? = nil,
        terminal: String? = nil,
        workspacePath: String? = nil
    ) -> HyperliteAgentRouting {
        HyperliteAgentRouting(
            bundleID: bundleID,
            terminal: terminal,
            terminalID: nil,
            tmuxSession: nil,
            tmuxPane: nil,
            workspacePath: workspacePath
        )
    }

    private static func session(
        revision: UInt64 = 1,
        title: String = "Session",
        updatedAt: Date = Date(timeIntervalSince1970: 10),
        action: HyperliteAgentPendingAction? = nil,
        routing: HyperliteAgentRouting = routing()
    ) -> HyperliteAgentSession {
        HyperliteAgentSession(
            id: "claude:one",
            provider: "claude",
            profile: "claude-code",
            sessionID: "one",
            parentID: nil,
            project: "hyperlite",
            title: title,
            phase: .processing,
            source: "hook",
            revision: revision,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: updatedAt,
            messages: [],
            latestResult: nil,
            action: action,
            routing: routing,
            openInClient: true
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
