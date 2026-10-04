import AppKit
import SwiftUI

struct HyperlitePullRequestPanelRow: View {
    static let layout = HyperlitePullRequestRowLayout.titleFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    let toggleReview: () -> Void

    @State private var hoverPresented = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var rowHovering = false

    var body: some View {
        HStack(spacing: 4) {
            HyperlitePullRequestReviewToggle(
                row: row,
                status: reviewStatus,
                quiet: !rowHovering,
                action: toggleReview
            )
            HyperlitePullRequestRowContent(
                row: row,
                reviewStatus: reviewStatus,
                openIssue: openIssue,
                openPullRequest: openPullRequest
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(HyperlitePullRequestRowContent.accessibilityLabel(
                for: row,
                reviewStatus: reviewStatus
            ))
            .accessibilityAction { openPullRequest() }
            .accessibilityAction(
                named: Text(row.issueLabel.map { "Open issue \($0)" } ?? "Open pull request")
            ) { row.issueURL == nil ? openPullRequest() : openIssue() }
        }
        .contentShape(Rectangle())
        .onHover(perform: handleHover)
        .popover(isPresented: $hoverPresented, arrowEdge: .trailing) {
            HyperlitePullRequestHoverCard(row: row, reviewStatus: reviewStatus)
        }
    }

    private func openPullRequest() {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openIssue() {
        guard let url = row.issueURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleHover(_ hovering: Bool) {
        rowHovering = hovering
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            let delay: Duration = hovering ? .milliseconds(350) : .milliseconds(200)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hoverPresented = hovering
        }
    }
}

struct HyperlitePullRequestReviewToggle: View {
    let row: HyperlitePullRequestRow
    let status: HyperlitePullRequestReviewStatus
    var quiet = false
    let action: () -> Void

    private var canToggle: Bool {
        status == .reviewed || (
            row.status == .current &&
                !row.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var icon: String {
        switch status {
        case .unreviewed: "square"
        case .reviewed: "checkmark.square.fill"
        case .stale: "exclamationmark.square.fill"
        }
    }

    private var color: Color {
        switch status {
        case .unreviewed: HyperliteTheme.mutedText.color
        case .reviewed: HyperliteTheme.cyan.color
        case .stale: HyperliteTheme.orange.color
        }
    }

    private var help: String {
        switch status {
        case .unreviewed where row.status != .current ||
            row.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            "Refresh current GitHub data before marking this pull request reviewed"
        case .unreviewed:
            "Mark reviewed by me for head \(String(row.headRefOID.prefix(7)))"
        case .reviewed:
            "Clear reviewed-by-me mark"
        case .stale:
            "Review mark is stale; mark head \(String(row.headRefOID.prefix(7))) reviewed"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .opacity(quiet && status == .unreviewed ? 0.28 : 1)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(help)
        .accessibilityLabel("Reviewed by me")
        .accessibilityValue(status.accessibilityLabel)
        .accessibilityHint(help)
    }
}
