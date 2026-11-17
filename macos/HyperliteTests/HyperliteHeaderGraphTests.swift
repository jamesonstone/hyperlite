import Foundation

enum HyperliteHeaderGraphTests {
    static func run() throws {
        let facts = try sampleFacts()
        let segments = HyperliteHeaderGraphLayout.segments(from: facts)
        expect(segments.map(\.id) == facts.map(\.id), "segments keep fact order, got \(segments.map(\.id))")
        expect(segments.first { $0.id == "open" }?.weight == 2, "open shares the count 2")
        expect(segments.first { $0.id == "open" }?.ink == .primary, "open uses primary text")
        expect(segments.first { $0.id == "feedback" }?.ink == .red, "feedback stays an alert color")
        expect(segments.first { $0.id == "stale10" }?.ink == .orange, "stale work stays attention color")
        expect(segments.first { $0.id == "ready" }?.ink == .green, "ready uses green")
        expect(segments.first { $0.id == "fresh" }?.ink == .cyan, "updated today uses cyan")
        expect(segments.first { $0.id == "oldest" }?.sharesScale == false, "oldest is an end cap")
        expect(segments.first { $0.id == "oldest" }?.valueText == "33d", "oldest shows its age, got \(segments)")
        expect(segments.first { $0.id == "oldest" }?.ink == .muted, "oldest stays muted")

        let failing = HyperliteHeaderGraphLayout.segments(from: [
            .init(id: "failing", text: "4 failing CI", help: "failed checks", tone: .alert),
        ])
        expect(failing.first?.ink == .red && failing.first?.weight == 4, "failing CI is a red count segment")

        testProportions()
        testOldestStaysFixedWhenCountsGrow()
        testNarrowWindowStillFits()
        testCaptions()
    }

    private static func testProportions() {
        let segments = [
            segment("open", "10 open", "10", 10, true),
            segment("projects", "2 projects", "2", 2, true),
            segment("oldest", "oldest 40d", "40d", 0, false),
        ]
        let available: CGFloat = 200
        let widths = HyperliteHeaderGraphLayout.widths(segments: segments, available: available)
        expect(widths.count == 3, "one width per segment")
        expect(near(widths[2], HyperliteHeaderGraphLayout.fixedSegment), "oldest keeps the fixed cap, got \(widths)")
        let flex = widths[0] + widths[1]
        expect(near(widths[0] / flex, 10.0 / 12.0), "open takes its share of the count scale, got \(widths)")
        expect(widths[0] > widths[1], "the larger count is wider")
        expect(sumsToAvailable(widths, available: available), "widths and gaps fill the strip, got \(widths)")
    }

    private static func testOldestStaysFixedWhenCountsGrow() {
        let small = layout(open: 2, projects: 1)
        let large = layout(open: 80, projects: 1)
        expect(near(small[2], large[2]), "oldest does not grow when counts grow, got \(small) \(large)")
        expect(large[0] > small[0], "open grows when its count grows")
    }

    private static func testNarrowWindowStillFits() {
        let segments = (0..<12).map { segment("s\($0)", "\($0)", "\($0)", Double($0 + 1), true) }
            + [segment("oldest", "oldest 9d", "9d", 0, false)]
        let widths = HyperliteHeaderGraphLayout.widths(segments: segments, available: 30)
        expect(widths.allSatisfy { $0 >= 0 }, "segments never go negative, got \(widths)")
        expect(sumsToAvailable(widths, available: 30), "a tight strip still accounts for its width, got \(widths)")
        expect(widths.contains { $0 < HyperliteHeaderGraphLayout.fixedSegment }, "the end cap shrinks when the strip is tight")
    }

    private static func testCaptions() {
        expect(
            HyperliteHeaderGraphLayout.caption(width: 10_000, text: "2 open", valueText: "2") == .full,
            "a wide segment shows the label and count"
        )
        let valueWidth = HyperliteHeaderGraphLayout.textWidth("2") + 6
        expect(
            HyperliteHeaderGraphLayout.caption(width: valueWidth, text: "2 open", valueText: "2") == .value,
            "a mid-width segment keeps the count"
        )
        expect(
            HyperliteHeaderGraphLayout.caption(width: valueWidth - 1, text: "2 open", valueText: "2") == .none,
            "a sliver leaves the words for hover"
        )
    }

    private static func layout(open: Double, projects: Double) -> [CGFloat] {
        HyperliteHeaderGraphLayout.widths(segments: [
            segment("open", "\(Int(open)) open", "\(Int(open))", open, true),
            segment("projects", "\(Int(projects)) projects", "\(Int(projects))", projects, true),
            segment("oldest", "oldest 33d", "33d", 0, false),
        ], available: 320)
    }

    private static func segment(
        _ id: String, _ text: String, _ valueText: String, _ weight: Double, _ sharesScale: Bool
    ) -> HyperliteHeaderGraphLayout.Segment {
        .init(
            id: id, text: text, valueText: valueText, help: "", weight: weight,
            sharesScale: sharesScale, tone: .neutral, ink: .secondary
        )
    }

    private static func sumsToAvailable(_ widths: [CGFloat], available: CGFloat) -> Bool {
        let gaps = HyperliteHeaderGraphLayout.gap * CGFloat(max(0, widths.count - 1))
        guard available >= gaps else { return widths.allSatisfy { $0 == 0 } }
        return near(widths.reduce(0, +) + gaps, available)
    }

    private static func near(_ value: CGFloat, _ expected: CGFloat) -> Bool {
        abs(value - expected) < 0.75
    }

    private static func sampleFacts() throws -> [HyperliteQuickFact] {
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
        return HyperliteQuickFacts.facts(
            model: HyperlitePullRequestPanelModel(scan: scan, hideIdle: true, now: now), now: now
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
