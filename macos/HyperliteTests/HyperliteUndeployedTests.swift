import Foundation

enum HyperliteUndeployedTests {
    static func run() throws {
        let scan = try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: Data("""
        {"schema_version": 1, "generated_at": "2026-10-06T12:00:00Z", "refresh_interval_seconds": 300,
         "projects": [
          {"id": "/a", "name": "a", "path": "/a", "repository": "o/a", "status": "current", "pull_requests": [],
           "workflows": {"catalog": [], "runs": [], "deployments": [],
            "pipeline_alerts": [{"kind": "deploy", "name": "deploy", "conclusion": "FAILURE", "observed_at": "2026-10-05T16:44:45Z"}],
            "deploys": {"checked_at": "2026-10-06T12:00:55.160197Z",
             "pipelines": [{"file": "deploy.yaml", "name": "deploy", "conclusion": "FAILURE",
               "url": "https://github.com/o/a/actions/runs/1", "attempt_at": "2026-10-05T16:44:06Z",
               "last_success_at": "2026-10-02T19:26:12Z"}],
             "pull_requests": [
               {"number": 12, "title": "feat: ship :sparkles:", "url": "https://github.com/o/a/pull/12",
                "head_ref_name": "GH-11", "merged_at": "2026-10-05T16:41:03Z"},
               {"number": 10, "title": "fix(GH-9): b", "merged_at": "2026-10-04T10:00:00Z"}]}}},
          {"id": "/b", "name": "b", "path": "/b", "repository": "p/b", "status": "current", "pull_requests": [],
           "workflows": {"catalog": [], "runs": [], "deployments": [],
            "deploys": {"checked_at": "2026-10-06T12:00:00Z",
             "pipelines": [{"file": "deploy.yaml", "name": "deploy", "conclusion": "SKIPPED", "attempt_at": "2026-10-05T17:05:53Z"}],
             "pull_requests": [{"number": 81, "title": "x", "merged_at": "2026-10-05T17:00:00Z"}]}}},
          {"id": "/c", "name": "c", "path": "/c", "repository": "o/c", "status": "current", "pull_requests": [],
           "workflows": {"catalog": [], "runs": [], "deployments": [], "deploys": {"checked_at": "2026-10-06T12:00:00Z"}}}
         ], "errors": [], "warnings": []}
        """.utf8))
        let now = try date("2026-10-06T12:00:00Z")
        let model = HyperlitePullRequestPanelModel(scan: scan, hideIdle: true, now: now)
        expect(model.undeployed.map(\.section.id) == ["/b", "/a"],
               "behind projects are listed newest attempt first, even when hidden as idle")
        expect(HyperliteUndeployedPresentation.summary(model.undeployed) == "3 PRs · 2 projects", "the band counts PRs and projects")

        let items = HyperlitePanelListItem.items(model: model, collapsed: [])
        expect(items.map(\.id) == [
            "undeployed-band", "undeployed:/b", "undeployed:/b#81", "undeployed:/a", "undeployed:/a#12", "undeployed:/a#10",
        ], "the band leads the list; got \(items.map(\.id))")
        expect(Set(items.map(\.id)).count == items.count, "band items have unique identities")
        let folded = HyperlitePanelListItem.items(model: model, collapsed: [HyperliteUndeployedPresentation.bandID])
        expect(folded.map(\.id) == ["undeployed-band"], "collapsing the band hides its projects and rows")
        let projectFolded = HyperlitePanelListItem.items(model: model, collapsed: ["undeployed:/b"])
        expect(projectFolded.map(\.id) == [
            "undeployed-band", "undeployed:/a", "undeployed:/a#12", "undeployed:/a#10", "undeployed:/b",
        ], "a collapsed project keeps its line, drops its rows, and sinks to the bottom; got \(projectFolded.map(\.id))")

        let a = model.undeployed[1]
        expect(a.runURL?.absoluteString == "https://github.com/o/a/actions/runs/1", "the project line opens the failed run")
        expect(HyperliteUndeployedPresentation.pipelineLabel(a.pipelines[0], now: now) == "deploy ✕ 19h", "failure label")
        expect(HyperliteUndeployedPresentation.pipelineLabel(model.undeployed[0].pipelines[0], now: now) == "deploy skipped 18h",
               "skip label")
        expect(HyperliteUndeployedPresentation.lastDeployLabel(a.pipelines[0], now: now) == "last deploy 3d ago", "last deploy age")
        expect(model.undeployed[0].runURL == nil &&
               HyperliteUndeployedPresentation.lastDeployLabel(model.undeployed[0].pipelines[0], now: now) == nil,
               "without a run link the line never falls back to the Actions listing")
        expect(HyperliteUndeployedPresentation.issueLabel(a.pullRequests[0]) == "GH-11" &&
               HyperliteUndeployedPresentation.issueLabel(a.pullRequests[1]) == "GH-9", "issue from branch or title")

        let status = try require(scan.projects[0].workflows?.deploys)
        expect(HyperliteUndeployedPresentation.badgeCount(status) == 2, "the heading badge counts undeployed PRs")
        expect(HyperliteUndeployedPresentation.badgeCount(HyperliteDeployStatus(
            pipelines: status.pipelines, pullRequests: []
        )) == 1, "without merged PRs the badge counts failing pipelines")
        expect(scan.projects[2].workflows?.deploys?.isBehind == false, "a status without pipelines is not behind")
        expect(HyperliteOpenPRProjectStageKind.forSection(model.sections[2], chips: [], undeployed: true) == .alert,
               "a behind deploy lights the lantern")

        let facts = HyperliteQuickFacts.facts(model: model, now: now)
        let fact = try require(facts.first { $0.id == "undeployed" })
        expect(fact.text == "3 not deployed" && fact.tone == .attention, "the quick fact counts undeployed PRs in amber")
        expect(facts.firstIndex { $0.id == "undeployed" } == 2, "not deployed is the first fact after the totals")
    }

    private static func date(_ text: String) throws -> Date {
        try require(ISO8601DateFormatter().date(from: text))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            FileHandle.standardError.write(Data("FAIL: missing value\n".utf8))
            exit(1)
        }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
