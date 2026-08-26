import Foundation

enum HyperlitePaletteTests {
    static func run() {
        testCommandEntries()
        testProjectEntries()
        testSearchFiltering()
        testNoteEntries()
        testRemoveProjectEntries()
        testSelenizedApplicationThemeTokens()
        testResponsivePaletteSizing()
    }

    private static func testCommandEntries() {
        let entries = HyperliteInteractionModel.commandEntries(
            threads: [],
            agentIslandEnabled: true
        )
        let ids = Set(entries.map(\.id))
        expect(ids.contains("action:show-dashboard"), "commands should include Dashboard switching")
        expect(ids.contains("action:show-pinboard"), "commands should include Pinboard switching")
        expect(ids.contains("action:add-pinboard-note"), "commands should include Pinboard note creation")
        expect(ids.contains("action:add-pinboard-section"), "commands should include Pinboard section creation")
        expect(ids.contains("action:open-pinboard-archive"), "commands should include Pinboard archive")
        expect(ids.contains("action:refresh"), "commands should include refresh")
        expect(ids.contains("action:force-cache-refresh"),
               "commands should include forced cache refresh")
        expect(ids.contains("action:copy-open-pr-merge-prompt"),
               "commands should include copy open PR merge prompt")
        let forceRefresh = entries.first { $0.id == "action:force-cache-refresh" }
        expect(forceRefresh?.kind == .action(.forceCacheRefresh),
               "forced cache refresh should dispatch its dedicated action")
        expect(forceRefresh?.subtitle.localizedCaseInsensitiveContains("cached errors") == true,
               "forced cache refresh should explain stale error recovery")
        expect(ids.contains("action:settings"), "commands should include settings")
        expect(ids.contains("action:add-project"), "commands should include add project")
        expect(ids.contains("action:remove-project"), "commands should include remove project")
        let island = entries.first { $0.id == "action:toggle-agent-island" }
        expect(island?.title == "Turn Agent Island Off",
               "enabled island should offer the off command")
        expect(island?.kind == .action(.toggleAgentIsland),
               "island command should dispatch the presentation toggle")
        let disabledIsland = HyperliteInteractionModel.commandEntries(
            threads: [],
            agentIslandEnabled: false
        ).first { $0.id == "action:toggle-agent-island" }
        expect(disabledIsland?.title == "Turn Agent Island On",
               "disabled island should offer the on command")
        expect(!entries.contains { $0.id.hasPrefix("prune:") },
               "commands should not expose worktree pruning")
    }

    private static func testProjectEntries() {
        let fixture = projectFixture()
        let collapsedExpansion: Set<String> = []
        let collapsed = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: collapsedExpansion
        )
        expect(collapsed.count == 2, "collapsed projects should show only configured headers")
        expect(collapsed.map(\.title) == ["kit", "flx"],
               "project order should follow configured projects")

        let whitespaceQuery = "  \n"
        let whitespaceExpansion = HyperliteInteractionModel.effectiveProjectExpansion(
            projects: fixture.projects,
            expandedProjects: collapsedExpansion,
            query: whitespaceQuery
        )
        let whitespaceSearch = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: whitespaceExpansion
        )
        expect(whitespaceSearch == collapsed,
               "a trimmed-empty search should preserve manual collapsed state")

        let expanded = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: [fixture.projects[0].id]
        )
        expect(expanded.count == 6, "expanded project should expose every PR and lane")
        expect(expanded[0].id == "project:/repo/kit", "kit header should remain first")
        expect(expanded.filter { $0.id.hasPrefix("project-pr:") }.count == 2,
               "all project pull requests should be visible")
        expect(expanded.filter { $0.id.hasPrefix("project-lane:") }.count == 2,
               "all project lanes should be visible")
        expect(expanded[5].id == "project:/repo/flx", "flx should remain collapsed")
    }

    private static func testSearchFiltering() {
        let fixture = projectFixture()
        let manuallyExpanded: Set<String> = []
        let childQuery = "ship feature"
        let childExpansion = HyperliteInteractionModel.effectiveProjectExpansion(
            projects: fixture.projects,
            expandedProjects: manuallyExpanded,
            query: childQuery
        )
        let childSearchable = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: childExpansion
        )
        let childMatch = HyperliteInteractionModel.filteredEntries(
            childSearchable,
            query: childQuery
        )
        expect(childMatch.map(\.id) == ["project:/repo/kit", "project-pr:/repo/kit:owner/kit#7"],
               "search should find a child PR from an initially collapsed project")

        let worktreeQuery = "/worktrees/kit"
        let worktreeExpansion = HyperliteInteractionModel.effectiveProjectExpansion(
            projects: fixture.projects,
            expandedProjects: manuallyExpanded,
            query: worktreeQuery
        )
        let worktreeSearchable = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: worktreeExpansion
        )
        let worktreeMatch = HyperliteInteractionModel.filteredEntries(
            worktreeSearchable,
            query: worktreeQuery
        )
        expect(worktreeMatch.map(\.id) == [
            "project:/repo/kit", "project-lane:/repo/kit:/worktrees/kit/GH-7",
        ], "search should find a child worktree from an initially collapsed project")

        let parentQuery = "KIT"
        let parentExpansion = HyperliteInteractionModel.effectiveProjectExpansion(
            projects: fixture.projects,
            expandedProjects: manuallyExpanded,
            query: parentQuery
        )
        let parentSearchable = HyperliteInteractionModel.projectEntries(
            projects: fixture.projects,
            pullRequests: fixture.scan,
            expandedProjects: parentExpansion
        )
        let parentMatch = HyperliteInteractionModel.filteredEntries(
            parentSearchable,
            query: parentQuery
        )
        expect(parentMatch.count == 5 && parentMatch.allSatisfy {
            $0.id.contains("/repo/kit") || $0.parentProjectID == "/repo/kit"
        }, "a project-name match should retain all expanded children")

        let commands = HyperliteInteractionModel.filteredEntries(
            HyperliteInteractionModel.commandEntries(
                threads: [],
                agentIslandEnabled: true
            ),
            query: "ADD"
        )
        expect(commands.map(\.id) == [
            "action:add-pinboard-note", "action:add-pinboard-section", "action:add-project",
        ],
               "command search should be case insensitive")
    }

    private static func testRemoveProjectEntries() {
        let projects = projectFixture().projects
        let entries = HyperliteInteractionModel.removeProjectEntries(projects: projects)
        expect(entries.map(\.title) == ["kit", "flx"],
               "remove-project selection should contain configured projects only")
        expect(entries.allSatisfy {
            if case .action(.removeProject(_)) = $0.kind { return true }
            return false
        }, "remove-project rows should carry only configuration actions")
    }

    private static func testNoteEntries() {
        let entries = HyperliteInteractionModel.noteEntries(results: [
            HyperliteNoteSearchResult(
                noteID: .pinned,
                filename: "pinned.md",
                date: nil,
                snippet: "Repository paths",
                matchKind: .exact,
                score: 2
            ),
            HyperliteNoteSearchResult(
                noteID: .daily("2026-08-02"),
                filename: "2026-08-02.md",
                date: "2026-08-02",
                snippet: "Related database work",
                matchKind: .semantic,
                score: 0.8
            ),
        ])
        expect(entries.map(\.title) == ["Pinned", "2026-08-02"],
               "note search entries should retain pinned and daily identities")
        expect(entries[0].kind == .action(.focusPinnedNote),
               "pinned result should focus the permanent editor")
        expect(entries[1].kind == .action(.openDailyNote("2026-08-02")),
               "daily result should open its date")
        expect(entries[1].subtitle.contains("semantic"),
               "semantic results should be identified in the shared palette")
    }

    private static func testSelenizedApplicationThemeTokens() {
        expect(HyperliteTheme.canvas.hex == 0x053d48,
               "application canvas should use Selene Selenized Dark bg_0")
        expect(HyperliteTheme.surface.hex == 0x0e4956,
               "elevated application surfaces should use Selene Selenized Dark bg_1")
        expect(HyperliteTheme.elevatedSurface.hex == 0x275b69,
               "inputs and dividers should use Selene Selenized Dark bg_2")
        expect(HyperliteTheme.primaryText.hex == 0xc8d7d8,
               "application text should use Selene Selenized Dark fg_1")
        expect(HyperliteTheme.red.hex == 0xfd564e,
               "application errors should use Selene Selenized Dark red")
        expect(HyperliteTheme.orange.hex == 0xf38649,
               "application attention should use Selene Selenized Dark orange")
        expect(HyperliteTheme.green.hex == 0x80b83c,
               "application success should use Selene Selenized Dark green")
        expect(HyperliteTheme.blue.hex == 0x0096f5,
               "application controls should use Selene Selenized Dark blue")
        expect(HyperliteTheme.cyan.hex == 0x39c7b9,
               "application focus should use Selene Selenized Dark cyan")
    }

    private static func testResponsivePaletteSizing() {
        let roomy = HyperlitePaletteLayout.size(containerWidth: 900, containerHeight: 800)
        expect(roomy.width == 560 && roomy.height == 480,
               "a roomy window should use the floating palette maximum size")

        let minimumWindow = HyperlitePaletteLayout.size(
            containerWidth: 480,
            containerHeight: 580
        )
        expect(minimumWindow.width == 432 && minimumWindow.height == 480,
               "the palette should preserve responsive margins at the minimum window size")

        let compact = HyperlitePaletteLayout.size(containerWidth: 300, containerHeight: 300)
        expect(compact.width == 252 && compact.height == 204,
               "the palette should remain contained in smaller proposed sizes")
    }

    private static func projectFixture() -> (
        projects: [HyperliteProjectLocation],
        scan: HyperliteProjectPullRequestScan
    ) {
        let main = HyperliteProjectLane(
            id: "/repo/kit", branch: "main", path: "/repo/kit",
            primary: true, detached: false
        )
        let worktree = HyperliteProjectLane(
            id: "/worktrees/kit/GH-7", branch: "GH-7", path: "/worktrees/kit/GH-7",
            primary: false, detached: false
        )
        let projects = [
            HyperliteProjectLocation(
                id: "/repo/kit", name: "kit", path: "/repo/kit",
                repository: "owner/kit", lanes: [main, worktree]
            ),
            HyperliteProjectLocation(
                id: "/repo/flx", name: "flx", path: "/repo/flx",
                repository: "owner/flx", lanes: []
            ),
        ]
        let pullRequests = [
            HyperliteProjectPullRequest(
                id: "owner/kit#7", number: 7, title: "Ship feature",
                url: "https://github.com/owner/kit/pull/7", headRefName: "GH-7",
                headRefOID: "head-7",
                isDraft: false, hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: Date()
            ),
            HyperliteProjectPullRequest(
                id: "owner/kit#8", number: 8, title: "Draft cleanup",
                url: "https://github.com/owner/kit/pull/8", headRefName: "GH-8",
                headRefOID: "head-8",
                isDraft: true, hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: Date()
            ),
        ]
        let scan = HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(), observedAt: Date(),
            rateLimit: nil, refreshIntervalSeconds: 300,
            projects: [HyperliteProjectPullRequests(
                id: "/repo/kit", name: "kit", path: "/repo/kit", repository: "owner/kit",
                status: .current, message: nil, checkedAt: Date(), observedAt: Date(),
                pullRequests: pullRequests
            )],
            errors: [], warnings: []
        )
        return (projects, scan)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
