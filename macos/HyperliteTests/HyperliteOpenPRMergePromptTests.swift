import Foundation

enum HyperliteOpenPRMergePromptTests {
    static func run() {
        testDurableInstructions()
        testRowObservations()
        testEmptyVisibleList()
        testVisibleRowsFollowHideDrafts()
        testCommandCopyLabels()
    }

    private static func testDurableInstructions() {
        let text = HyperliteOpenPRMergePrompt.text(rows: [row(
            number: 187, isDraft: false, conflict: true, threads: 4
        )])
        expect(text.hasPrefix(HyperliteOpenPRMergePrompt.instructions),
               "copied text should start with the durable merge-ready instructions")
        expect(text.contains("`gh`"),
               "instructions should tell the agent to use gh")
        expect(text.contains("Do not merge"),
               "instructions should forbid merging unless later asked")
        expect(text.contains("behind the default branch"),
               "instructions should tell the agent to check default-branch freshness")
    }

    private static func testRowObservations() {
        let url = URL(string: "https://github.com/owner/one/pull/187")
        let text = HyperliteOpenPRMergePrompt.text(rows: [
            row(number: 187, url: url, isDraft: false, conflict: true, threads: 4),
            row(number: 12, isDraft: true, conflict: false, threads: nil),
            row(number: 3, isDraft: false, conflict: false, threads: 0),
            row(number: 9, isDraft: false, conflict: false, threads: 1),
        ])
        expect(text.contains("- owner/one#187 — https://github.com/owner/one/pull/187 — ready; merge conflicts; 4 unresolved review threads"),
               "ready conflicting rows should include URL and known hints")
        expect(text.contains("- owner/one#12 — draft; no merge conflicts; unresolved review threads unknown"),
               "draft rows without a URL should omit that segment")
        expect(text.contains("- owner/one#3 — ready; no merge conflicts; no unresolved review threads"),
               "zero review threads should be explicit")
        expect(text.contains("- owner/one#9 — ready; no merge conflicts; 1 unresolved review thread"),
               "a single review thread should stay singular")
    }

    private static func testEmptyVisibleList() {
        let text = HyperliteOpenPRMergePrompt.text(rows: [])
        expect(text.contains("## Visible Open PRs"),
               "empty copy text should still include the list heading")
        expect(text.contains("(none)"),
               "empty visible lists should record that no rows were shown")
        expect(!text.contains("owner/one#"),
               "empty visible lists should not invent pull-request observations")
    }

    private static func testVisibleRowsFollowHideDrafts() {
        let rows = [
            row(number: 8, isDraft: false, conflict: false, threads: 0),
            row(number: 12, isDraft: true, conflict: false, threads: 0),
        ]
        var filter = HyperlitePullRequestFilter()
        filter.hideDrafts = true
        let visible = HyperliteDashboardListPresentation.displayedPullRequests(
            rows, filter: filter, sort: .recent, customOrder: [], isReordering: false
        )
        let text = HyperliteOpenPRMergePrompt.text(rows: visible)
        expect(visible.map(\.number) == [8],
               "copied rows should follow the visible hide-drafts list")
        expect(text.contains("owner/one#8") && !text.contains("owner/one#12"),
               "the prompt should omit hidden draft rows")
        let reordering = HyperliteDashboardListPresentation.displayedPullRequests(
            rows, filter: filter, sort: .recent, customOrder: [], isReordering: true
        )
        expect(reordering.map(\.number) == [8, 12],
               "reorder mode should copy every loaded row currently shown")
    }

    private static func testCommandCopyLabels() {
        let idle = HyperliteInteractionModel.commandEntries(
            threads: [],
            agentIslandEnabled: true,
            visibleOpenPullRequestCount: 2,
            mergePromptCopied: false
        ).first { $0.id == "action:copy-open-pr-merge-prompt" }
        expect(idle?.kind == .action(.copyOpenPRMergePrompt),
               "Command-K should dispatch the merge-prompt copy action")
        expect(idle?.title == "Copy Open PR Merge Prompt",
               "idle command title should describe the copy action")
        expect(idle?.subtitle.contains("2 visible PRs") == true,
               "idle command subtitle should count visible rows")
        let copied = HyperliteInteractionModel.commandEntries(
            threads: [],
            agentIslandEnabled: false,
            visibleOpenPullRequestCount: 0,
            mergePromptCopied: true
        ).first { $0.id == "action:copy-open-pr-merge-prompt" }
        expect(copied?.title == "Copied Open PR Merge Prompt",
               "copied command title should confirm the pasteboard write")
        expect(copied?.subtitle == "Copied to clipboard",
               "copied command subtitle should confirm the clipboard")
        let empty = HyperliteInteractionModel.commandEntries(
            threads: [],
            agentIslandEnabled: true,
            visibleOpenPullRequestCount: 0,
            mergePromptCopied: false
        ).first { $0.id == "action:copy-open-pr-merge-prompt" }
        expect(empty?.subtitle == "No visible open pull requests",
               "empty visible lists should explain why copy will no-op")
    }

    private static func row(
        number: Int,
        url: URL? = nil,
        isDraft: Bool,
        conflict: Bool,
        threads: Int?
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: "pr-\(number)", reviewID: "pr-\(number)", repository: "owner/one",
            status: .current, number: number, title: "pr-\(number)", url: url,
            headRefOID: "head-\(number)", isDraft: isDraft,
            hasMergeConflict: conflict, unresolvedReviewThreads: threads,
            updatedAt: Date(timeIntervalSince1970: 1_785_850_000)
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
