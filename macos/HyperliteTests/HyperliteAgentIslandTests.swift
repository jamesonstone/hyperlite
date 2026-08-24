import Foundation

enum HyperliteAgentIslandTests {
    @MainActor
    static func run() {
        testPreferenceDefaultsAndPersistence()
        testLaunchPolicy()
        testLiveTaskGrouping()
        testWorkspaceOrder()
    }

    @MainActor
    private static func testPreferenceDefaultsAndPersistence() {
        let suite = "hyperlite.agent-island-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fail("isolated preference store should be available")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = HyperliteAgentIslandPreference(defaults: defaults)
        expect(initial.isEnabled, "missing island preference defaults on")
        expect(defaults.object(forKey: HyperliteAgentIslandPreference.key) == nil,
               "reading the default does not write a migration value")
        initial.setEnabled(false)
        expect(!initial.isEnabled, "preference owner publishes explicit off")
        let relaunched = HyperliteAgentIslandPreference(defaults: defaults)
        expect(!relaunched.isEnabled, "explicit off persists across preference owners")
        relaunched.toggle()
        expect(relaunched.isEnabled, "toggle restores the floating island")
        let restored = HyperliteAgentIslandPreference(defaults: defaults)
        expect(restored.isEnabled, "explicit on persists across preference owners")
    }

    private static func testLaunchPolicy() {
        expect(HyperliteAgentIslandLaunchPolicy.destination(
            featureEnabled: false,
            hasConsent: true,
            islandEnabled: true
        ) == .dashboard, "the full preview rollback opens Dashboard")
        expect(HyperliteAgentIslandLaunchPolicy.destination(
            featureEnabled: true,
            hasConsent: false,
            islandEnabled: true
        ) == .onboarding, "missing consent keeps onboarding visible")
        expect(HyperliteAgentIslandLaunchPolicy.destination(
            featureEnabled: true,
            hasConsent: true,
            islandEnabled: true
        ) == .island, "consented default launch remains island first")
        expect(HyperliteAgentIslandLaunchPolicy.destination(
            featureEnabled: true,
            hasConsent: true,
            islandEnabled: false
        ) == .dashboard, "an explicitly hidden island opens Dashboard")
        expect(HyperliteAgentIslandLaunchPolicy.showsPanel(
            featureEnabled: true,
            hasConsent: true,
            islandEnabled: true
        ), "all presentation gates create the panel")
        expect(!HyperliteAgentIslandLaunchPolicy.showsPanel(
            featureEnabled: true,
            hasConsent: true,
            islandEnabled: false
        ), "the island preference closes the panel only")
        expect(HyperliteAgentIslandLaunchPolicy.tracksSessions(
            featureEnabled: true,
            hasConsent: true
        ), "tracking remains active independently of island presentation")
    }

    private static func testLiveTaskGrouping() {
        let sessions = [
            session(id: "cursor:one", provider: "claude-hooks", profile: "cursor", phase: .processing),
            session(id: "claude:one", provider: "claude-hooks", profile: "claude-code",
                    phase: .waitingForApproval),
            session(id: "claude:two", provider: "claude-hooks", profile: "claude-code",
                    phase: .waitingForInput),
            session(id: "cursor:two", provider: "claude-hooks", profile: "cursor", phase: .starting),
            session(id: "qwen:one", provider: "qwen", profile: "qwen-code", phase: .processing),
            session(id: "codex:one", provider: "codex", profile: "codex", phase: .idle),
            session(id: "done", provider: "codex", profile: "codex", phase: .completed),
            session(id: "failed", provider: "codex", profile: "codex", phase: .error),
            session(id: "ended", provider: "codex", profile: "codex", phase: .ended),
            session(id: "synthetic", provider: "codex", profile: "codex",
                    phase: .processing, synthetic: true),
        ]
        let groups = HyperliteAgentTaskPresentation.groups(
            sessions: sessions,
            integrations: [
                integration(id: "claude-code", name: "Claude Code", provider: "claude-hooks"),
                integration(id: "cursor", name: "Cursor", provider: "claude-hooks"),
                integration(id: "qwen-code", name: "Qwen Code", provider: "qwen"),
                integration(id: "codex", name: "Codex", provider: "codex"),
            ]
        )
        expect(groups.map(\.profile) == ["claude-code", "cursor", "qwen-code", "codex"],
               "groups sort attention, active names, then idle")
        expect(groups.map(\.displayName) == ["Claude Code", "Cursor", "Qwen Code", "Codex"],
               "group headings use exact client profile names")
        expect(groups[1].sessions.map(\.id) == ["cursor:one", "cursor:two"],
               "session order remains stable inside each client")
        expect(groups.flatMap(\.sessions).count == 6,
               "terminal and synthetic rows are absent from Agent Tasks")
        expect(groups[0].sessions[0].provider == groups[1].sessions[0].provider,
               "different clients remain separate even when their adapter provider matches")
    }

    private static func testWorkspaceOrder() {
        expect(HyperliteWorkspace.allCases == [.dashboard, .pinboard, .sessions],
               "Agent Tasks remains the third workspace after Pinboard")
    }

    private static func session(
        id: String,
        provider: String,
        profile: String,
        phase: HyperliteAgentSessionPhase,
        synthetic: Bool = false
    ) -> HyperliteAgentSession {
        HyperliteAgentSession(
            id: id,
            provider: provider,
            profile: profile,
            sessionID: id,
            parentID: nil,
            project: "hyperlite",
            title: id,
            phase: phase,
            source: "hook",
            revision: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            messages: [],
            latestResult: nil,
            action: nil,
            routing: HyperliteAgentRouting(
                bundleID: nil,
                terminal: nil,
                terminalID: nil,
                tmuxSession: nil,
                tmuxPane: nil,
                workspacePath: nil
            ),
            openInClient: false,
            synthetic: synthetic
        )
    }

    private static func integration(
        id: String,
        name: String,
        provider: String
    ) -> HyperliteAgentIntegration {
        HyperliteAgentIntegration(
            id: id,
            name: name,
            provider: provider,
            detected: true,
            enabled: true,
            actionMode: "observe",
            target: nil,
            message: nil
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
