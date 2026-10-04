import Foundation

@main
struct HyperliteInteractionModelTests {
    static func main() throws {
        try testStructuredDiagnosticDecoding()
        HyperlitePaletteTests.run()
        HyperliteAppearanceTests.run()
        HyperlitePullRequestHoverTests.run()
        testSelectionClamping()
        testProcessEnvironment()
        HyperliteTypographyTests.run()
        try HyperliteProjectIndexTests.run()
        try HyperlitePullRequestTests.run()
        try HyperliteOpenPRControlsTests.run()
        HyperliteOpenPRMergePromptTests.run()
        try HyperliteWorkflowActivityTests.run()
        HyperlitePipelineAlertTests.run()
        HyperlitePullRequestSectionsTests.run()
        HyperliteOpenPRWatchStageTests.run()
        HyperliteWorkspaceNavigationTests.run()
        HyperliteIssueReferenceTests.run()
        HyperliteActivityPollScheduleTests.run()
        HyperliteAmbientRefreshScheduleTests.run()
        try HyperlitePullRequestJumpTests.run()
        try HyperlitePullRequestPanelModelTests.run()
        HyperliteFailedPipelineTests.run()
        try HyperliteProjectIgnoreTests.run()
        try HyperlitePullRequestReviewMarkerTests.run()
        HyperliteRateLimitTests.run()
        print("Hyperlite interaction model tests passed")
    }

    private static func testProcessEnvironment() {
        let localBin = NSHomeDirectory() + "/.local/bin"
        let inherited = HyperliteProcessEnvironment.inheriting([
            "PATH": "/custom/bin:/opt/homebrew/bin:/usr/bin",
            "HYPERLITE_TEST": "preserved",
        ])
        expect(
            inherited["PATH"] ==
                "/custom/bin:/opt/homebrew/bin:/usr/bin:/usr/local/bin:\(localBin)",
            "helper PATH should preserve order, avoid duplicates, and add Intel Homebrew and ~/.local/bin"
        )
        expect(inherited["HYPERLITE_TEST"] == "preserved",
               "helper environment should preserve unrelated inherited values")

        let fallback = HyperliteProcessEnvironment.inheriting([:])
        expect(
            fallback["PATH"] ==
                "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:\(localBin)",
            "helper PATH should include system, Homebrew, and ~/.local/bin when PATH is absent"
        )
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
        expect(diagnostic.code == "worktree_prunable", "structured diagnostic code should decode")
        expect(diagnostic.repositoryPath == "/repo/kit", "repository path should decode")
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
