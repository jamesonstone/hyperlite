import Foundation

@main
struct HyperliteInteractionModelTests {
    static func main() throws {
        try testStructuredDiagnosticDecoding()
        testCommandEntries()
        testProjectEntries()
        testSelectionClamping()
        testHoverSummaryLimit()
        print("Hyperlite interaction model tests passed")
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

    private static func testCommandEntries() {
        let diagnostic = prunableDiagnostic()
        let entries = HyperliteInteractionModel.commandEntries(
            items: [item(repository: "kit", path: "/repo/kit", branch: "GH-5")],
            errors: [],
            warnings: [diagnostic]
        )
        expect(entries.map(\.id).contains("action:refresh"), "commands should include refresh")
        expect(entries.map(\.id).contains("action:settings"), "commands should include settings")
        expect(entries.map(\.id).contains("action:diagnostics"), "commands should include diagnostics")
        expect(entries.contains { $0.id.hasPrefix("prune:") }, "commands should include prune")
        expect(entries.contains { $0.id.hasPrefix("item:") }, "commands should include work items")
    }

    private static func testProjectEntries() {
        let items = [
            item(repository: "kit", path: "/repo/kit", branch: "GH-5"),
            item(repository: "kit", path: "/repo/kit", branch: "GH-3"),
            item(repository: "flx", path: "/repo/flx", branch: "GH-1"),
        ]
        let collapsed = HyperliteInteractionModel.projectEntries(
            items: items,
            expandedProjects: []
        )
        expect(collapsed.count == 2, "collapsed projects should show only headers")
        expect(collapsed.map(\.title) == ["kit", "flx"], "project order should follow source items")

        let expanded = HyperliteInteractionModel.projectEntries(
            items: items,
            expandedProjects: ["/repo/kit"]
        )
        expect(expanded.count == 4, "expanded project should expose only its own items")
        expect(expanded[0].id == "project:/repo/kit", "kit header should remain selected")
        expect(expanded[3].id == "project:/repo/flx", "flx should remain collapsed")
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
        let longPath = "/" + String(repeating: "nested/", count: 70)
        let summary = HyperliteInteractionModel.hoverSummary(
            for: item(repository: "kit", path: longPath, branch: "GH-5")
        )
        expect(summary.count <= 300, "hover summary should never exceed 300 characters")
        expect(summary.hasSuffix("…"), "truncated summary should show an ellipsis")
    }

    private static func item(repository: String, path: String, branch: String) -> HyperliteWorkItem {
        HyperliteWorkItem(
            repository: repository,
            github: "owner/\(repository)",
            repositoryPath: path,
            branch: branch,
            base: "main",
            state: "branch",
            publication: "published",
            nextAction: "continue_work",
            updatedAt: Date(),
            worktree: HyperliteWorktree(
                path: path,
                staged: 0,
                unstaged: 0,
                untracked: 0,
                conflicted: 0,
                ahead: 0,
                aheadBase: 1
            ),
            pullRequest: nil
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
