import Foundation

enum HyperlitePaletteTests {
    static func run() {
        testCommandEntries()
        testProjectEntries()
        testSearchFiltering()
        testRemoveProjectEntries()
    }

    private static func testCommandEntries() {
        let entries = HyperliteInteractionModel.commandEntries(threads: [])
        let ids = Set(entries.map(\.id))
        expect(ids.contains("action:refresh"), "commands should include refresh")
        expect(ids.contains("action:settings"), "commands should include settings")
        expect(ids.contains("action:add-project"), "commands should include add project")
        expect(ids.contains("action:remove-project"), "commands should include remove project")
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
            HyperliteInteractionModel.commandEntries(threads: []),
            query: "ADD"
        )
        expect(commands.map(\.id) == ["action:add-project"],
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
                isDraft: false, updatedAt: Date()
            ),
            HyperliteProjectPullRequest(
                id: "owner/kit#8", number: 8, title: "Draft cleanup",
                url: "https://github.com/owner/kit/pull/8", headRefName: "GH-8",
                isDraft: true, updatedAt: Date()
            ),
        ]
        let scan = HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(), observedAt: Date(),
            refreshIntervalSeconds: 300,
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
