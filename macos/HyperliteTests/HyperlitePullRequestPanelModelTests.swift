import Foundation

enum HyperlitePullRequestPanelModelTests {
    static func run() throws {
        let scan = try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: Data("""
        {"schema_version": 1, "generated_at": "2026-10-04T12:00:00Z", "refresh_interval_seconds": 300,
         "projects": [
          {"id": "/a", "name": "a", "path": "/a", "repository": "o/a", "status": "current", "pull_requests": [
            {"id": "o/a#1", "number": 1, "title": "one", "url": "https://github.com/o/a/pull/1",
             "head_ref_name": "GH-1", "head_ref_oid": "h1", "is_draft": false, "unresolved_review_threads": 0,
             "updated_at": "2026-10-04T11:00:00Z"}]},
          {"id": "/b", "name": "b", "path": "/b", "repository": "o/b", "status": "current", "pull_requests": []}
         ], "errors": [], "warnings": []}
        """.utf8))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let model = HyperlitePullRequestPanelModel(scan: scan, hideIdle: true, now: now)
        expect(model.rowCount == 1 && model.sections.count == 2, "model counts rows and sections")
        expect(model.visibleSections.map(\.id) == ["/a"] && model.hiddenSections.map(\.id) == ["/b"] &&
               model.hiddenCount == 1, "hide-idle splits the project without rows into the hidden list")
        let showAll = HyperlitePullRequestPanelModel(scan: scan, hideIdle: false, now: now)
        expect(showAll.organizations.map(\.name) == ["o"] && showAll.organizations[0].sections.count == 2 &&
               showAll.organizations[0].pullRequestCount == 1, "projects group under their GitHub organization")
        expect(showAll.organizations[0].sectionsOrdered(collapsed: ["/a"]).map(\.id) == ["/b", "/a"],
               "collapsed projects sink to the bottom of their organization")
        expect(showAll.organizations[0].sectionsOrdered(collapsed: []).map(\.id) == ["/a", "/b"],
               "expanded projects keep their order")
        expect(showAll.visibleSections.count == 2 && showAll.hiddenSections.isEmpty, "show-all lists every project")

        let cache = HyperlitePullRequestPanelModelCache()
        let first = cache.model(scan: scan, hideIdle: true, now: now)
        let again = cache.model(scan: scan, hideIdle: true, now: now)
        let toggled = cache.model(scan: scan, hideIdle: false, now: now)
        expect(first.visibleSections.map(\.id) == again.visibleSections.map(\.id) &&
               toggled.visibleSections.count == 2, "the cache rebuilds only when its inputs change")
        let eyeGroups = HyperliteHideIdlePresentation.groups(model.sections)
        expect(eyeGroups.map(\.name) == ["o"] && eyeGroups[0].sections.map(\.repository) == ["o/a", "o/b"],
               "the eye lists every project grouped by organization")
        expect(HyperliteHideIdlePresentation.watchLabel(repository: "o/b", ignored: true).hasPrefix("o/b is ignored"),
               "each project's eye states its watch state")
        expect(HyperliteHideIdlePresentation.hint(hideIdle: true, hiddenCount: 1).hasPrefix("1 project hidden") &&
               HyperliteHideIdlePresentation.hint(hideIdle: true, hiddenCount: 3).hasPrefix("3 projects hidden"),
               "the hint counts hidden projects")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
