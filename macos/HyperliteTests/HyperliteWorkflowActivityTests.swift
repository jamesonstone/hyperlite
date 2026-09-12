import Foundation

enum HyperliteWorkflowActivityTests {
    static let now = Date(timeIntervalSince1970: 1_789_250_000)
    static let utc = TimeZone(identifier: "UTC")!

    static func run() throws {
        try testDecodingWithAndWithoutActivity()
        testChipDerivation()
        testFreshnessBoundary()
        testSyntheticDeploymentChip()
        testLabelsAndSummary()
        testCompactChipsAndHover()
    }

    private static func testDecodingWithAndWithoutActivity() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(HyperliteProjectPullRequestScan.self, from: Data(activityJSON.utf8))
        let workflows = scan.projects[0].workflows
        expect(workflows?.catalog.map(\.name) == ["ci", "deploy"], "catalog decodes in order")
        expect(workflows?.runs.first?.isActive == true && workflows?.runs.first?.pullRequestNumber == 7,
               "pull request run decodes with number and active status")
        expect(workflows?.deployments.first?.isActive == true, "deployment decodes")
        expect(workflows?.treeOID == "tree-1" && workflows?.message == nil, "optional fields decode")
        expect(scan.activityPolicy?.allowed == true && scan.activityPolicy?.reason == "ok" &&
            scan.activityPolicy?.activeRunCount == 2 && scan.activityPolicy?.pollsThisWindow == 3,
            "activity policy decodes")
        let legacy = try decoder.decode(HyperliteProjectPullRequestScan.self, from: Data(legacyJSON.utf8))
        expect(legacy.projects[0].workflows == nil && legacy.activityPolicy == nil,
               "legacy JSON without workflow fields still decodes")
    }

    private static func testChipDerivation() {
        let activity = sampleActivity(observedAt: now.addingTimeInterval(-60))
        let chips = HyperliteWorkflowStripPresentation.chips(activity: activity, now: now)
        expect(chips.map(\.id) == ["ci.yaml", "deploy.yaml", "main.yaml", "codeql"],
               "catalog order first, then observed non-catalog workflows; got \(chips.map(\.id))")
        expect(chips[0].state == .running(since: now.addingTimeInterval(-180)),
               "fresh active run renders as running since its start")
        expect(chips[1].state == .running(since: now.addingTimeInterval(-240)) && chips[1].deployment != nil,
               "active deployment attaches to the deploy workflow chip")
        expect(chips[2].state == .success && chips[3].state == .failure, "completed runs map by conclusion")
        expect(HyperliteWorkflowStripPresentation.hasFreshActiveRun(scan: scan(activity), now: now),
               "fresh active run is detected")
        expect(
            HyperliteWorkflowStripPresentation.nextFreshnessExpiry(scan: scan(activity), now: now)
                == now.addingTimeInterval(60),
            "freshness expires 120 seconds after observation"
        )
        expect(HyperliteWorkflowStripPresentation.chips(activity: nil, now: now).isEmpty, "no activity yields no chips")
    }

    private static func testFreshnessBoundary() {
        let fresh = sampleActivity(observedAt: now.addingTimeInterval(-119))
        expect(HyperliteWorkflowStripPresentation.chips(activity: fresh, now: now)[0].isRunning,
               "119 seconds old is still fresh")
        let staleObserved = now.addingTimeInterval(-121)
        let stale = HyperliteWorkflowStripPresentation.chips(
            activity: sampleActivity(observedAt: staleObserved), now: now
        )
        expect(stale[0].state == .staleRunning(lastSeen: staleObserved),
               "121 seconds old renders as last seen, never animated")
        expect(!HyperliteWorkflowStripPresentation.hasFreshActiveRun(
            scan: scan(sampleActivity(observedAt: staleObserved)), now: now
        ), "stale active run is not fresh")
        expect(HyperliteWorkflowStripPresentation.nextFreshnessExpiry(
            scan: scan(sampleActivity(observedAt: staleObserved)), now: now
        ) == nil, "already stale observation has no pending expiry")
    }

    private static func testSyntheticDeploymentChip() {
        var activity = sampleActivity(observedAt: now.addingTimeInterval(-10))
        activity.catalog = [HyperliteWorkflowDefinition(file: "ci.yaml", name: "ci")]
        activity.runs = []
        let chips = HyperliteWorkflowStripPresentation.chips(activity: activity, now: now)
        expect(chips.map(\.id) == ["ci.yaml", "deployment:prod"],
               "an active deployment without a deploy workflow gets its own chip; got \(chips.map(\.id))")
        expect(chips[1].title == "prod" && chips[1].isRunning, "synthetic chip is titled by environment")
    }

    private static func testLabelsAndSummary() {
        expect(HyperliteWorkflowStripPresentation.elapsedLabel(since: now.addingTimeInterval(-42), now: now) == "42s",
               "seconds label")
        expect(HyperliteWorkflowStripPresentation.elapsedLabel(since: now.addingTimeInterval(-192), now: now) == "3m 12s",
               "minutes label")
        expect(HyperliteWorkflowStripPresentation.elapsedLabel(since: now.addingTimeInterval(-3840), now: now) == "1h 04m",
               "hours label")
        let seen = Date(timeIntervalSince1970: 1_789_222_920)
        expect(HyperliteWorkflowStripPresentation.lastSeenLabel(seen, timeZone: utc) == "last seen 14:22",
               "last seen uses HH:mm; got \(HyperliteWorkflowStripPresentation.lastSeenLabel(seen, timeZone: utc))")
        let idle = HyperliteWorkflowChip(id: "ci.yaml", title: "ci", state: .idle, run: nil, deployment: nil)
        expect(HyperliteWorkflowStripPresentation.headerSummary(chips: [idle], now: now) == "no workflow runs observed",
               "idle-only summary")
        let chips = HyperliteWorkflowStripPresentation.chips(
            activity: sampleActivity(observedAt: now.addingTimeInterval(-60)), now: now
        )
        let summary = HyperliteWorkflowStripPresentation.headerSummary(chips: chips, now: now, timeZone: utc)
        expect(summary.hasPrefix("workflows: ci running for 3m 00s, deploy running for 4m 00s, main succeeded, codeql failed"),
               "summary names every notable chip; got \(summary)")
    }

    private static func testCompactChipsAndHover() {
        let chips = HyperliteWorkflowStripPresentation.chips(
            activity: sampleActivity(observedAt: now.addingTimeInterval(-60)), now: now
        )
        let compact = HyperliteWorkflowStripPresentation.compactChips(chips)
        expect(compact.visible.map(\.id) == ["ci.yaml", "deploy.yaml", "codeql"] && compact.hiddenCount == 1,
               "compact strip keeps running and failed chips and counts the rest")
        let card = HyperliteWorkflowHoverPresentation.snapshot(chip: chips[0], now: now, timeZone: utc)
        expect(card.statusLine == "running · 3m 00s", "hover status; got \(card.statusLine)")
        expect(card.triggerLine == "pull_request · #7 GH-7 · run #9", "hover trigger; got \(card.triggerLine)")
        expect(card.links.map(\.label) == ["Open run"], "hover links the run")
        let deploy = HyperliteWorkflowHoverPresentation.snapshot(chip: chips[1], now: now, timeZone: utc)
        expect(deploy.deploymentLine == "prod · in progress" && deploy.links.map(\.label) == ["Open run", "Open deployment log"],
               "hover shows deployment and both links; got \(deploy.deploymentLine) \(deploy.links.map(\.label))")
    }

    static func sampleActivity(observedAt: Date) -> HyperliteProjectWorkflowActivity {
        HyperliteProjectWorkflowActivity(
            catalog: [
                HyperliteWorkflowDefinition(file: "ci.yaml", name: "ci"),
                HyperliteWorkflowDefinition(file: "deploy.yaml", name: "deploy"),
                HyperliteWorkflowDefinition(file: "main.yaml", name: "main"),
            ],
            runs: [
                HyperliteWorkflowRun(
                    file: "ci.yaml", name: "ci", scope: "pull_request", pullRequestNumber: 7, headRefName: "GH-7",
                    status: "IN_PROGRESS", event: "pull_request", runNumber: 9, url: "https://github.com/o/r/actions/runs/9",
                    createdAt: now.addingTimeInterval(-180), updatedAt: now.addingTimeInterval(-60)
                ),
                HyperliteWorkflowRun(
                    file: "main.yaml", name: "main", scope: "tip", status: "COMPLETED", conclusion: "SUCCESS",
                    createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-500)
                ),
                HyperliteWorkflowRun(
                    file: "deploy.yaml", name: "deploy", scope: "tip", status: "IN_PROGRESS",
                    url: "https://github.com/o/r/actions/runs/10",
                    createdAt: now.addingTimeInterval(-240), updatedAt: now.addingTimeInterval(-60)
                ),
                HyperliteWorkflowRun(
                    file: "codeql", name: "codeql", scope: "tip", status: "COMPLETED", conclusion: "FAILURE",
                    createdAt: now.addingTimeInterval(-700), updatedAt: now.addingTimeInterval(-650)
                ),
            ],
            deployments: [HyperliteDeployment(
                environment: "prod", state: "IN_PROGRESS", logURL: "https://example.com/log",
                createdAt: now.addingTimeInterval(-200), updatedAt: now.addingTimeInterval(-100)
            )],
            treeOID: "tree-1", observedAt: observedAt
        )
    }

    private static func scan(_ activity: HyperliteProjectWorkflowActivity) -> HyperliteProjectPullRequestScan {
        HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: now, checkedAt: now, observedAt: now, rateLimit: nil,
            refreshIntervalSeconds: 300,
            projects: [HyperliteProjectPullRequests(
                id: "/repo/one", name: "one", path: "/repo/one", repository: "owner/one", status: .current,
                message: nil, checkedAt: now, observedAt: now, pullRequests: [], workflows: activity
            )],
            errors: [], warnings: []
        )
    }

    private static let activityJSON = """
    {"schema_version":1,"generated_at":"2026-09-12T20:00:00Z","refresh_interval_seconds":300,
     "activity_policy":{"allowed":true,"reason":"ok","next_eligible_at":"2026-09-12T20:01:00Z",
       "active_run_count":2,"interval_seconds":60,"max_burst_seconds":1800,"polls_this_window":3},
     "projects":[{"id":"/repo/one","name":"one","path":"/repo/one","repository":"owner/one","status":"current",
       "pull_requests":[],
       "workflows":{"catalog":[{"file":"ci.yaml","name":"ci","url":"https://github.com/owner/one/actions/workflows/ci.yaml"},
         {"file":"deploy.yaml","name":"deploy"}],
         "runs":[{"file":"ci.yaml","name":"ci","scope":"pull_request","pull_request_number":7,"status":"IN_PROGRESS",
           "created_at":"2026-09-12T19:58:00Z","updated_at":"2026-09-12T19:59:00Z"}],
         "deployments":[{"environment":"prod","state":"IN_PROGRESS","created_at":"2026-09-12T19:50:00Z","updated_at":"2026-09-12T19:55:00Z"}],
         "tree_oid":"tree-1","checked_at":"2026-09-12T19:59:00Z","observed_at":"2026-09-12T19:59:00Z"}}],
     "errors":[],"warnings":[]}
    """

    private static let legacyJSON = """
    {"schema_version":1,"generated_at":"2026-09-12T20:00:00Z","refresh_interval_seconds":300,
     "projects":[{"id":"/repo/one","name":"one","path":"/repo/one","repository":"owner/one","status":"current","pull_requests":[]}],
     "errors":[],"warnings":[]}
    """

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
