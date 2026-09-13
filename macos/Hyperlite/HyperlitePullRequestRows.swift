import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperlitePullRequestPanelRow: View {
    static let layout = HyperlitePullRequestRowLayout.titleFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    let pinned: Bool
    let compact: Bool
    var showRepository = true
    @Binding var draggedRowID: String?
    let toggleReview: () -> Void
    let togglePin: () -> Void
    let move: (String, String) -> Void
    let moveBy: (String, Int) -> Void

    static let dragHandleRestOpacity: Double = 0.18
    static let pinRestOpacity: Double = 0.2

    @State private var hoverPresented = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var rowHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .opacity(rowHovering ? 1 : Self.dragHandleRestOpacity)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onDrag {
                    draggedRowID = row.id
                    return NSItemProvider(object: row.id as NSString)
                }
            Button(action: togglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(pinned ? HyperliteTheme.cyan.color : HyperliteTheme.mutedText.color)
                    .opacity(pinned || rowHovering ? 1 : Self.pinRestOpacity)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pinned ? "Unpin from top" : "Pin to top")
            .accessibilityLabel(pinned ? "Unpin pull request" : "Pin pull request")
            HyperlitePullRequestReviewToggle(
                row: row,
                status: reviewStatus,
                quiet: !rowHovering,
                action: toggleReview
            )
            HyperlitePullRequestRowContent(
                row: row,
                reviewStatus: reviewStatus,
                compact: compact,
                showRepository: showRepository,
                openNumber: openNumber,
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
                named: Text(row.numberOpensIssue ? "Open linked issue" : "Open pull request number")
            ) { openNumber() }
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text.identifier],
            delegate: HyperliteReorderDropDelegate(
                targetID: row.id,
                draggedID: $draggedRowID,
                move: move
            )
        )
        .onHover(perform: handleHover)
        .popover(isPresented: $hoverPresented, arrowEdge: .trailing) {
            HyperlitePullRequestHoverCard(row: row, reviewStatus: reviewStatus)
        }
        .accessibilityAction(named: "Move up") { moveBy(row.id, -1) }
        .accessibilityAction(named: "Move down") { moveBy(row.id, 1) }
        .accessibilityValue(pinned ? "pinned" : "unpinned")
    }

    private func openPullRequest() {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openNumber() {
        guard let url = row.numberURL else { return }
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

struct HyperlitePinnedSectionDropTarget: View {
    @Binding var draggedRowID: String?
    let pin: (String) -> Void

    var body: some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text.identifier],
                delegate: HyperliteSectionPinDropDelegate(
                    draggedID: $draggedRowID,
                    pin: pin
                )
            )
    }
}

struct HyperliteSectionPinDropDelegate: DropDelegate {
    @Binding var draggedID: String?
    let pin: (String) -> Void

    func performDrop(info _: DropInfo) -> Bool {
        if let draggedID { pin(draggedID) }
        draggedID = nil
        return true
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
