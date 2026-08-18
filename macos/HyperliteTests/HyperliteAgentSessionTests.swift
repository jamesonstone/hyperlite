import Foundation

enum HyperliteAgentSessionTests {
    static func run() throws {
        HyperliteAgentSessionPolicyTests.run()
        let snapshot = try testSnapshotDecoding()
        try testActionEncoding()
        testPopupTransitions(snapshot)
        testActionAndRoutePresentation(snapshot)
        testNotchGeometry()
    }

    private static func testSnapshotDecoding() throws -> HyperliteAgentSessionSnapshot {
        let data = Data("""
        {
          "schema": "agent_session_snapshot.v1",
          "generation": 4,
          "generated_at": "2026-08-17T12:00:00Z",
          "sessions": [{
            "id": "claude:session-1",
            "provider": "claude",
            "profile": "claude-code",
            "session_id": "session-1",
            "project": "hyperlite",
            "title": "Notch work",
            "phase": "waiting_for_approval",
            "source": "hook",
            "revision": 3,
            "created_at": "2026-08-17T11:59:00Z",
            "updated_at": "2026-08-17T12:00:00Z",
            "messages": [{"role":"user","text":"Implement it"}],
            "action": {
              "request_id":"request-1", "kind":"approval", "title":"Allow Bash?",
              "context":"git status --short", "complete_context":true,
              "can_allow_once":true, "can_deny":true, "can_answer":false,
              "can_allow_session":false, "can_revoke":false
            },
            "routing": {"bundle_id":"com.anthropic.claudefordesktop","workspace_path":"/tmp/hyperlite"},
            "open_in_client": true
          }],
          "integrations": [{
            "id":"claude-code", "name":"Claude Code", "provider":"claude",
            "detected":true, "enabled":true, "action_mode":"blocking"
          }]
        }
        """.utf8)
        let record = try HyperliteAgentWireRecord.decode(data)
        guard case let .snapshot(snapshot) = record else { fail("snapshot record expected") }
        expect(snapshot.generation == 4, "snapshot generation")
        expect(snapshot.attentionCount == 1, "attention count")
        expect(snapshot.activeCount == 0, "active count")
        expect(snapshot.sessions[0].action?.requestID == "request-1", "exact request id")
        expect(snapshot.sessions[0].messages.count == 1, "bounded messages")
        return snapshot
    }

    private static func testPopupTransitions(_ snapshot: HyperliteAgentSessionSnapshot) {
        expect(snapshot.popupTransition(from: nil) == .attention, "initial live request expands")
        expect(snapshot.popupTransition(from: snapshot) == nil, "retained attention does not reopen")

        let attention = snapshot.sessions[0]
        let processing = copy(attention, phase: .processing, action: .some(nil))
        let processingSnapshot = copy(snapshot, sessions: [processing])
        expect(processingSnapshot.popupTransition(from: processingSnapshot) == nil,
               "unchanged non-attention input stays collapsed")
        expect(snapshot.popupTransition(from: processingSnapshot) == .attention,
               "newly urgent attention expands")

        let revised = copy(attention, revision: attention.revision + 1)
        let revisedSnapshot = copy(snapshot, sessions: [revised])
        expect(revisedSnapshot.popupTransition(from: snapshot) == .attention,
               "changed action identity expands")

        let completed = copy(revised, phase: .completed, action: .some(nil))
        let completedSnapshot = copy(revisedSnapshot, sessions: [completed])
        expect(completedSnapshot.popupTransition(from: revisedSnapshot) == .completion,
               "new completion expands")
        expect(completedSnapshot.popupTransition(from: completedSnapshot) == nil,
               "retained completion does not reopen")
        expect(completedSnapshot.popupTransition(from: nil) == nil,
               "discovered historical completion stays collapsed")

        let failed = copy(revised, phase: .error, action: .some(nil))
        let failedSnapshot = copy(revisedSnapshot, sessions: [failed])
        expect(failedSnapshot.popupTransition(from: revisedSnapshot) == .completion,
               "new error transition expands")
    }

    private static func testActionAndRoutePresentation(_ snapshot: HyperliteAgentSessionSnapshot) {
        let session = snapshot.sessions[0]
        expect(session.actionIdentity == HyperliteAgentActionIdentity(
            sessionID: session.id,
            requestID: "request-1",
            revision: 3
        ), "pending action identity includes exact revision")
        expect(session.routeDestination?.label == "Open Claude", "application route names the exact bundle")
        let cursorRouting = HyperliteAgentRouting(
            bundleID: "com.todesktop.230313mzl4w4u92",
            terminal: nil,
            terminalID: nil,
            tmuxSession: nil,
            tmuxPane: nil,
            workspacePath: nil
        )
        let cursor = copy(session, profile: "cursor", routing: cursorRouting)
        expect(cursor.routeDestination?.label == "Open Cursor",
               "exact Cursor bundle names the owning app")

        let finderRouting = HyperliteAgentRouting(
            bundleID: nil,
            terminal: nil,
            terminalID: nil,
            tmuxSession: nil,
            tmuxPane: nil,
            workspacePath: "/tmp/hyperlite"
        )
        let finder = copy(session, routing: finderRouting)
        expect(finder.routeDestination == .finder, "workspace-only route uses Finder")
        expect(finder.routeDestination?.label == "Reveal in Finder", "Finder route is explicit")
    }

    private static func copy(
        _ snapshot: HyperliteAgentSessionSnapshot,
        sessions: [HyperliteAgentSession]
    ) -> HyperliteAgentSessionSnapshot {
        HyperliteAgentSessionSnapshot(
            schema: snapshot.schema,
            generation: snapshot.generation + 1,
            generatedAt: snapshot.generatedAt,
            sessions: sessions,
            integrations: snapshot.integrations
        )
    }

    private static func copy(
        _ session: HyperliteAgentSession,
        phase: HyperliteAgentSessionPhase? = nil,
        profile: String? = nil,
        revision: UInt64? = nil,
        action: HyperliteAgentPendingAction?? = nil,
        routing: HyperliteAgentRouting? = nil
    ) -> HyperliteAgentSession {
        HyperliteAgentSession(
            id: session.id,
            provider: session.provider,
            profile: profile ?? session.profile,
            sessionID: session.sessionID,
            parentID: session.parentID,
            project: session.project,
            title: session.title,
            phase: phase ?? session.phase,
            source: session.source,
            revision: revision ?? session.revision,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            messages: session.messages,
            latestResult: session.latestResult,
            action: action ?? session.action,
            routing: routing ?? session.routing,
            openInClient: session.openInClient
        )
    }

    private static func testActionEncoding() throws {
        let request = HyperliteAgentActionRequest(
            sessionID: "claude:session-1",
            requestID: "request-1",
            revision: 3,
            action: "allow_once",
            answers: nil
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        expect(object?["schema"] as? String == hyperliteAgentActionSchema, "action schema")
        expect(object?["session_id"] as? String == "claude:session-1", "canonical session id")
        expect(object?["request_id"] as? String == "request-1", "action request id")
        expect(object?["revision"] as? Int == 3, "action revision")
    }

    private static func testNotchGeometry() {
        let physical = HyperliteAgentNotchMetrics.detect(
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            safeAreaTop: 38,
            auxiliaryLeftWidth: 650,
            auxiliaryRightWidth: 650
        )
        expect(physical.hasPhysicalNotch, "physical notch detected")
        expect(physical.size.width >= 170 && physical.size.height == 38, "physical notch size")
        let fallback = HyperliteAgentNotchMetrics.detect(
            screenFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil
        )
        expect(!fallback.hasPhysicalNotch, "fallback display")
        let geometry = HyperliteAgentNotchGeometry(
            screenFrame: CGRect(x: 100, y: 50, width: 1_920, height: 1_080),
            metrics: fallback
        )
        let collapsed = geometry.frame(expanded: false)
        let expanded = geometry.frame(expanded: true)
        let emptyExpanded = geometry.frame(expanded: true, hasSessions: false)
        expect(collapsed.midX == expanded.midX, "top-edge frames stay centered")
        expect(collapsed.maxY == expanded.maxY, "top-edge frames stay anchored")
        expect(emptyExpanded.height == 150, "empty expanded surface stays compact")
        expect(HyperliteWorkspace.allCases.contains(.sessions), "sessions workspace exists")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
