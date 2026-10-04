import Foundation

enum HyperliteQuickFactsTests {
    static func run() throws {
        let scan = try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: Data("""
        {"schema_version": 1, "generated_at": "2026-10-04T12:00:00Z", "refresh_interval_seconds": 300,
         "projects": [
          {"id": "/a", "name": "a", "path": "/a", "repository": "o/a", "status": "current", "pull_requests": [
            {"id": "o/a#1", "number": 1, "title": "fresh", "url": "https://github.com/o/a/pull/1",
             "head_ref_name": "GH-1", "head_ref_oid": "h1", "is_draft": false, "unresolved_review_threads": 2,
             "updated_at": "2026-10-04T11:00:00Z"},
            {"id": "o/a#2", "number": 2, "title": "old", "url": "https://github.com/o/a/pull/2",
             "head_ref_name": "dependabot/x", "head_ref_oid": "h2", "is_draft": true, "unresolved_review_threads": 0,
             "updated_at": "2026-09-01T11:00:00Z"}]},
          {"id": "/b", "name": "b", "path": "/b", "repository": "o/b", "status": "cached", "ignored": true,
           "pull_requests": []}
         ], "errors": [], "warnings": []}
        """.utf8))
        let now = try HyperliteJSON.decoder.decode([Date].self, from: Data(#"["2026-10-04T12:00:00Z"]"#.utf8))[0]
        let facts = HyperliteQuickFacts.facts(
            model: HyperlitePullRequestPanelModel(scan: scan, hideIdle: true, now: now), now: now
        )
        let texts = facts.map(\.text)
        expect(Array(texts.prefix(2)) == ["2 open", "1 projects"], "open count and projects lead; got \(texts)")
        for expected in ["1 need feedback", "1 >10d", "1 >30d", "1 ready", "1 drafts", "1 updated today",
                         "1 bot", "1 ignored", "oldest 33d"] {
            expect(texts.contains(expected), "facts include \(expected); got \(texts)")
        }
        expect(!texts.contains { $0.contains("failing") || $0.contains("conflicts") }, "zero-count facts are omitted")
        expect(facts.first { $0.id == "feedback" }?.tone == .alert, "feedback reads as an alert")
        expect(HyperliteAppVersion.label(info: ["CFBundleShortVersionString": "1.2.0", "HyperliteCommit": "abc1234"])
            == "hyperlite v1.2.0 · abc1234", "release builds show version and commit")
        expect(HyperliteAppVersion.label(info: ["CFBundleShortVersionString": "abc1234", "HyperliteCommit": "abc1234"])
            == "hyperlite abc1234", "a commit-only version is not repeated")
        expect(HyperliteAppVersion.label(info: [
            "CFBundleShortVersionString": "1.0.0", "HyperliteDescribe": "v1.2.0-3-gabc1234", "HyperliteCommit": "abc1234",
        ]) == "hyperlite v1.2.0-3-gabc1234", "the describe string wins over the numeric bundle version")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
