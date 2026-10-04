import Foundation

enum HyperlitePullRequestJumpTests {
    static func run() throws {
        let parse = HyperlitePullRequestJump.parse
        expect(parse("kahlo 33") == HyperlitePullRequestJumpQuery(project: "kahlo", number: 33), "project then number")
        expect(parse("labcore ui #826")?.number == 826 && parse("labcore ui #826")?.project == "labcore ui",
               "multi-word projects and # prefix")
        expect(parse("dewey GH-12")?.number == 12 && parse("dewey pr17")?.number == 17, "GH- and PR prefixes")
        expect(parse("kahlo") == nil && parse("33") == nil && parse("kahlo abc") == nil,
               "a jump needs both a project and a number")

        let scan = try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: Data("""
        {"schema_version": 1, "generated_at": "2026-10-04T12:00:00Z", "refresh_interval_seconds": 300,
         "projects": [
          {"id": "/kahlo", "name": "kahlo", "path": "/kahlo", "repository": "o/kahlo", "status": "current",
           "pull_requests": [
            {"id": "o/kahlo#33", "number": 33, "title": "direct", "url": "https://github.com/o/kahlo/pull/33",
             "head_ref_name": "feature", "head_ref_oid": "h", "is_draft": false, "updated_at": "2026-10-04T11:00:00Z"},
            {"id": "o/kahlo#40", "number": 40, "title": "tracks 33", "url": "https://github.com/o/kahlo/pull/40",
             "head_ref_name": "GH-33", "head_ref_oid": "h2", "is_draft": false, "updated_at": "2026-10-04T11:00:00Z"}]},
          {"id": "/dewey", "name": "dewey", "path": "/dewey", "repository": "o/dewey", "status": "cached",
           "ignored": true, "pull_requests": []}
         ], "errors": [], "warnings": []}
        """.utf8))
        let entries = HyperlitePullRequestJump.entries(query: "kahlo 33", scan: scan) ?? []
        expect(entries.map(\.kind) == [
            .action(.selectPullRequest("/kahlo\u{1F}o/kahlo#33")),
            .action(.selectPullRequest("/kahlo\u{1F}o/kahlo#40")),
        ], "the PR-number match comes first, then the PR tracking issue 33; got \(entries.map(\.title))")
        expect(entries[0].title.hasPrefix("PR #33") && entries[1].title.hasPrefix("GH-33 → PR #40"),
               "titles say which number matched")
        expect(HyperlitePullRequestJump.entries(query: "kahlo 99", scan: scan) == nil,
               "no match falls back to ordinary filtering")
        expect(HyperlitePullRequestJump.sectionID(for: "/kahlo\u{1F}o/kahlo#33") == "/kahlo" &&
               HyperlitePullRequestJump.sectionID(for: "header:/kahlo") == "/kahlo" &&
               HyperlitePullRequestJump.sectionID(for: "quiet-ones") == nil,
               "rows and headings resolve to their project section")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
