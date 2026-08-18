import Foundation

enum HyperliteAgentSessionCompatibilityTests {
    static func run() throws {
        try testV2ActionQueue()
        try testHealthRecord()
        try testControlEncoding()
        try testV1ActionEncoding()
        try testQueueBoundAndUnknownSchema()
    }

    private static func testV2ActionQueue() throws {
        let data = Data("""
        {
          "schema":"agent_session_snapshot.v2", "generation":9,
          "generated_at":"2026-08-18T12:00:00Z",
          "sessions":[{
            "id":"claude:queue", "provider":"claude", "profile":"claude-code",
            "session_id":"queue", "project":"hyperlite", "title":"Queued work",
            "phase":"waiting_for_approval", "source":"hook", "revision":7,
            "created_at":"2026-08-18T11:59:00Z", "updated_at":"2026-08-18T12:00:00Z",
            "messages":[], "actions":[
              {"request_id":"one","kind":"approval","title":"First","context":"git status",
               "complete_context":true,"can_allow_once":true,"can_deny":true,"can_answer":false,
               "can_allow_session":false,"can_revoke":false,"revision":4},
              {"request_id":"two","kind":"question","title":"Second","context":"Choose",
               "complete_context":true,"can_allow_once":false,"can_deny":false,"can_answer":true,
               "can_allow_session":false,"can_revoke":false,"revision":7}
            ], "routing":{}, "open_in_client":false
          }], "integrations":[]
        }
        """.utf8)
        guard case let .snapshot(snapshot) = try HyperliteAgentWireRecord.decode(data) else {
            fail("v2 snapshot expected")
        }
        let session = snapshot.sessions[0]
        expect(session.pendingActionCount == 2, "v2 action queue decodes")
        expect(session.currentAction?.requestID == "one", "oldest exact request is current")
        expect(session.actionIdentity?.revision == 4, "action revision is independent of session revision")
    }

    private static func testHealthRecord() throws {
        let data = Data("""
        {"schema":"agent_integration_health.v1","provider":"codex","profile":"codex",
         "transport":"hook+app_server+rollout","connection_state":"idle",
         "last_event_at":"2026-08-18T12:00:00.123Z",
         "last_acknowledgement_at":"2026-08-18T12:00:01.456Z",
         "watchers_used":4,"watchers_limit":32,"filtered_count":2,"rejected_count":1,
         "self_test_result":"passed"}
        """.utf8)
        guard case let .health(health) = try HyperliteAgentWireRecord.decode(data) else {
            fail("health record expected")
        }
        expect(health.watchersUsed == 4 && health.watchersLimit == 32, "watcher utilization decodes")
        expect(health.selfTestResult == "passed", "self-test acknowledgement decodes")
        expect(health.lastEventAt != nil && health.lastAcknowledgementAt != nil,
               "fractional health timestamps decode")
    }

    private static func testControlEncoding() throws {
        let request = HyperliteAgentControlRequest(
            operation: "integration_self_test",
            profile: "codex",
            requestID: "test-id"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        expect(object?["schema"] as? String == hyperliteAgentControlSchema, "control schema")
        expect(object?["operation"] as? String == "integration_self_test", "control operation")
        expect(object?["request_id"] as? String == "test-id", "control request identity")
    }

    private static func testV1ActionEncoding() throws {
        let request = HyperliteAgentActionRequest(
            schema: hyperliteAgentActionSchemaV1,
            provider: "claude",
            sessionID: "claude:legacy",
            requestID: "legacy",
            revision: 9,
            action: "deny",
            answers: nil
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        expect(object?["schema"] as? String == hyperliteAgentActionSchemaV1,
               "v1 snapshot compatibility sends a v1 action")
    }

    private static func testQueueBoundAndUnknownSchema() throws {
        let action = """
        {"request_id":"one","kind":"approval","title":"First","context":"git status",
         "complete_context":true,"can_allow_once":true,"can_deny":true,"can_answer":false,
         "can_allow_session":false,"can_revoke":false,"revision":4}
        """
        let data = Data("""
        {"schema":"agent_session_snapshot.v2","generation":10,
         "generated_at":"2026-08-18T12:00:00Z","sessions":[{
         "id":"claude:bounded","provider":"claude","profile":"claude-code",
         "session_id":"bounded","project":"hyperlite","title":"Bounded",
         "phase":"waiting_for_approval","source":"hook","revision":10,
         "created_at":"2026-08-18T12:00:00Z","updated_at":"2026-08-18T12:00:00Z",
         "messages":[],"actions":[\(Array(repeating: action, count: 9).joined(separator: ","))],
         "routing":{},"open_in_client":false}],"integrations":[]}
        """.utf8)
        guard case let .snapshot(snapshot) = try HyperliteAgentWireRecord.decode(data) else {
            fail("bounded snapshot expected")
        }
        expect(snapshot.sessions[0].actions.count == hyperliteAgentMaxPendingActions,
               "native action queue enforces the shared bound")
        do {
            _ = try HyperliteAgentWireRecord.decode(Data("{\"schema\":\"unknown.v1\"}".utf8))
            fail("unknown schema was accepted")
        } catch { }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
