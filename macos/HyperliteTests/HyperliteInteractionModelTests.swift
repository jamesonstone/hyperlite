import Foundation

@main
struct HyperliteInteractionModelTests {
    static func main() async throws {
        try testSchemaV2Decoding()
        try testStructuredDiagnosticDecoding()
        testAttentionAndInformationalProjections()
        expect(!HyperliteFeatureFlags.inferredAttentionPresentation, "attention presentation hidden")
        testRowSummaryOnlyShowsAttention()
        testCommandEntries()
        testProjectEntries()
        testSelectionClamping()
        testHoverSummaryLimit()
        HyperliteTypographyTests.run()
        try HyperliteProjectIndexTests.run()
        try HyperlitePullRequestTests.run()
        try await HyperliteNotepadTests.run()
        print("Hyperlite interaction model tests passed")
    }

    private static func testSchemaV2Decoding() throws {
        let data = Data("""
        {
          "schema_version": 2,
          "generated_at": "2026-07-28T12:00:00Z",
          "remote_observed_at": "2026-07-28T11:59:00Z",
          "remote_refresh_interval_seconds": 300,
          "summary": {
            "projects": 1, "threads": 1, "attention": 1,
            "in_flight": 1, "completed": 0, "errors": 0, "warnings": 0
          },
          "threads": [{
            "id": "issue:owner/r2#7",
            "aliases": ["branch:owner/r2@GH-7"],
            "title": "R2 delivery",
            "goal": "Deliver object storage",
            "rationale": "Separate durable blobs from events.",
            "phase": "operationalizing",
            "active": true,
            "repositories": ["owner/r2"],
            "artifacts": [],
            "dependencies": [],
            "implications": [],
            "obligations": [],
            "evidence": [],
            "attention": [{
              "id": "moment:1", "kind": "reconcile", "summary": "Deployment remains",
              "action": "Confirm deployment ownership.",
              "why": "The merged PR does not deploy infrastructure.", "revision": "abc",
              "consequence": "The service may ship without infrastructure.",
              "valid_while": "The deployment obligation remains open.",
              "evidence_ids": [], "created_at": "2026-07-28T12:00:00Z", "seen": false
            }],
            "latest_material_revision": "abc",
            "why_now": "Deployment remains",
            "confidence": 0.9,
            "inference_status": "unavailable",
            "note": "Coordinate the bucket first.",
            "updated_at": "2026-07-28T12:00:00Z"
          }],
          "errors": [],
          "warnings": []
        }
        """.utf8)
        let decoder = decoder()
        let scan = try decoder.decode(HyperliteThreadScan.self, from: data)
        expect(scan.schemaVersion == 2, "schema v2 should decode")
        expect(scan.remoteRefreshIntervalSeconds == 300, "refresh interval should decode")
        expect(scan.threads[0].phase == .operationalizing, "lifecycle phase should decode")
        expect(scan.threads[0].hasUnseenAttention, "unseen revision should count as attention")
        expect(scan.threads[0].attention[0].action == "Confirm deployment ownership.",
               "expected cognitive action should decode")
        expect(scan.threads[0].attention[0].validWhile == "The deployment obligation remains open.",
               "attention validity should decode")
        expect(scan.threads[0].latestMaterialRevision == "abc", "seen revision anchor should decode")
        expect(scan.threads[0].note == "Coordinate the bucket first.", "optional notes should decode")
        expect(scan.threads[0].inferenceStatus == "unavailable", "degraded inference should decode")
    }

    private static func testStructuredDiagnosticDecoding() throws {
        let data = Data("""
        {
          "repository": "kit",
          "repository_path": "/repo/kit",
          "stage": "worktree",
          "message": "worktree is prunable: /stale/kit",
          "code": "worktree_prunable",
          "worktree_path": "/stale/kit"
        }
        """.utf8)
        let diagnostic = try JSONDecoder().decode(HyperliteDiagnostic.self, from: data)
        expect(diagnostic.isPrunableWorktree, "structured diagnostic should be actionable")
        expect(diagnostic.repositoryPath == "/repo/kit", "repository path should decode")
    }

    private static func testAttentionAndInformationalProjections() {
        let now = Date()
        let attention = thread(id: "attention", repository: "owner/r2", active: true, unseen: true, updatedAt: now)
        let activeOld = thread(
            id: "active-old",
            repository: "owner/event-sink",
            active: true,
            unseen: false,
            updatedAt: now.addingTimeInterval(-100 * 86_400)
        )
        let complete = thread(
            id: "complete",
            repository: "owner/r2",
            active: false,
            unseen: false,
            updatedAt: now.addingTimeInterval(-2 * 86_400)
        )
        let inactiveAttention = thread(
            id: "inactive-attention",
            repository: "owner/r2",
            active: false,
            unseen: true,
            updatedAt: now.addingTimeInterval(60)
        )
        let scan = scan(threads: [complete, inactiveAttention, activeOld, attention], now: now)
        expect(HyperlitePresentation.attentionThreads(scan: scan).map(\.id) == ["attention"],
               "the urgent projection should contain current attention only")
        expect(HyperlitePresentation.informationalThreads(scan: scan).map(\.id) == ["active-old"],
               "the informational projection should contain active threads without attention")
        expect(HyperlitePresentation.activeThreads(scan: scan).map(\.id) == ["attention", "active-old"],
               "the active count should cover both visible projections")
    }

    private static func testCommandEntries() {
        let entries = HyperliteInteractionModel.commandEntries(
            threads: [thread(id: "one", repository: "owner/kit")],
            warnings: [genericDiagnostic(), prunableDiagnostic()]
        )
        expect(entries.map(\.id).contains("action:refresh"), "commands should include refresh")
        expect(entries.map(\.id).contains("action:settings"), "commands should include settings")
        expect(!entries.map(\.id).contains("action:diagnostics"),
               "commands should not expose generic scan diagnostics")
        expect(entries.filter { $0.id.hasPrefix("prune:") }.count == 1,
               "only actionable diagnostics should produce prune commands")
        expect(entries.contains { $0.id.hasPrefix("thread:") }, "commands should include threads")
    }

    private static func testRowSummaryOnlyShowsAttention() {
        let ordinary = thread(id: "ordinary", repository: "owner/kit")
        let attention = thread(
            id: "attention", repository: "owner/kit", unseen: true,
            whyNow: "A decision is required"
        )
        expect(HyperlitePresentation.rowSummary(for: ordinary) == nil,
               "ordinary in-flight rows should stay quiet")
        expect(HyperlitePresentation.rowSummary(for: attention) == "A decision is required",
               "attention rows should explain why they need attention")
    }

    private static func testProjectEntries() {
        let threads = [
            thread(id: "one", repository: "owner/kit"),
            thread(id: "two", repository: "owner/kit"),
            thread(id: "three", repository: "owner/flx"),
        ]
        let collapsed = HyperliteInteractionModel.projectEntries(threads: threads, expandedProjects: [])
        expect(collapsed.count == 2, "collapsed projects should show only headers")
        expect(collapsed.map(\.title) == ["kit", "flx"], "project order should follow source threads")

        let expanded = HyperliteInteractionModel.projectEntries(
            threads: threads,
            expandedProjects: ["owner/kit"]
        )
        expect(expanded.count == 4, "expanded project should expose only its own threads")
        expect(expanded[0].id == "project:owner/kit", "kit header should remain selected")
        expect(expanded[3].id == "project:owner/flx", "flx should remain collapsed")
    }

    private static func testSelectionClamping() {
        expect(HyperliteInteractionModel.movedSelection(0, by: -1, count: 3) == 0,
               "selection should clamp at the start")
        expect(HyperliteInteractionModel.movedSelection(2, by: 1, count: 3) == 2,
               "selection should clamp at the end")
        expect(HyperliteInteractionModel.movedSelection(1, by: 1, count: 3) == 2,
               "selection should move within bounds")
        expect(HyperliteInteractionModel.movedSelection(4, by: 0, count: 2) == 1,
               "selection should recover after entries collapse")
    }

    private static func testHoverSummaryLimit() {
        let value = thread(
            id: "long",
            repository: "owner/kit",
            whyNow: String(repeating: "coordination boundary ", count: 30)
        )
        let summary = HyperliteInteractionModel.hoverSummary(for: value)
        expect(summary.count <= 300, "hover summary should never exceed 300 characters")
        expect(summary.hasSuffix("…"), "truncated summary should show an ellipsis")
    }

    private static func scan(threads: [HyperliteThread], now: Date) -> HyperliteThreadScan {
        HyperliteThreadScan(
            schemaVersion: 2,
            generatedAt: now,
            remoteObservedAt: now,
            remoteRefreshIntervalSeconds: 300,
            summary: HyperliteThreadSummary(
                projects: 2,
                threads: threads.count,
                attention: threads.filter(\.hasUnseenAttention).count,
                inFlight: threads.filter(\.active).count,
                completed: threads.filter { !$0.active }.count,
                errors: 0,
                warnings: 0
            ),
            projectIndex: [],
            threads: threads,
            errors: [],
            warnings: []
        )
    }

    private static func thread(
        id: String,
        repository: String,
        active: Bool = true,
        unseen: Bool = false,
        updatedAt: Date = Date(),
        whyNow: String = "In implementing"
    ) -> HyperliteThread {
        HyperliteThread(
            id: id,
            aliases: [],
            title: id,
            goal: "Goal for \(id)",
            rationale: "Rationale for \(id)",
            phase: active ? .implementing : .complete,
            active: active,
            repositories: [repository],
            artifacts: [],
            dependencies: [],
            implications: [],
            obligations: [],
            evidence: [],
            attention: unseen ? [
                HyperliteAttentionMoment(
                    id: "\(id)@revision",
                    kind: "know",
                    summary: whyNow,
                    action: "Update the working mental model.",
                    why: "A material change occurred.",
                    consequence: "Later decisions may use stale context.",
                    validWhile: "This is the latest material revision.",
                    revision: "revision",
                    evidenceIDs: [],
                    createdAt: updatedAt,
                    seen: false
                ),
            ] : [],
            latestMaterialRevision: "revision",
            whyNow: whyNow,
            confidence: 0.8,
            inferenceStatus: "not_configured",
            note: nil,
            updatedAt: updatedAt
        )
    }

    private static func prunableDiagnostic() -> HyperliteDiagnostic {
        HyperliteDiagnostic(
            repository: "kit",
            repositoryPath: "/repo/kit",
            stage: "worktree",
            message: "worktree is prunable: /stale/kit",
            code: "worktree_prunable",
            worktreePath: "/stale/kit"
        )
    }

    private static func genericDiagnostic() -> HyperliteDiagnostic {
        HyperliteDiagnostic(
            repository: "kit",
            repositoryPath: nil,
            stage: "github",
            message: "cached GitHub evidence is stale",
            code: nil,
            worktreePath: nil
        )
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
