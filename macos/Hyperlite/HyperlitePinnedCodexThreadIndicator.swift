import SwiftUI

struct HyperlitePinnedCodexThreadIndicator: View {
    @ObservedObject var state: HyperlitePinnedCodexThreadState
    @State private var isPresented = false

    private var presentation: HyperlitePinnedCodexThreadIndicatorPresentation {
        HyperlitePinnedCodexThreadPresentation.indicator(
            snapshot: state.snapshot,
            lastAvailableAt: state.lastAvailableAt
        )
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: presentation.systemImage)
                Text(presentation.countText)
                    .monospacedDigit()
            }
            .font(HyperliteTypography.semibold(11))
            .foregroundStyle(
                presentation.isMuted
                    ? HyperliteTheme.mutedText.color
                    : HyperliteTheme.secondaryText.color
            )
        }
        .buttonStyle(.bordered)
        .help(presentation.help)
        .accessibilityLabel(presentation.accessibilityLabel)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            HyperlitePinnedCodexThreadPopover(state: state)
                .padding(14)
                .frame(width: 340, alignment: .leading)
                .hyperliteTheme()
        }
    }
}

private struct HyperlitePinnedCodexThreadPopover: View {
    @ObservedObject var state: HyperlitePinnedCodexThreadState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Pinned Codex Threads")
                        .font(HyperliteTypography.semibold(12))
                    if state.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing pinned Codex threads")
                    }
                }
                Text(HyperlitePinnedCodexThreadPresentation.statusText(
                    snapshot: state.snapshot,
                    lastAvailableAt: state.lastAvailableAt
                ))
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
            }

            HyperliteThemeDivider()

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Codex threads")
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = state.snapshot {
            switch snapshot.availability {
            case .unavailable:
                Label(
                    snapshot.message ?? "Pinned Codex threads are unavailable",
                    systemImage: "pin.slash"
                )
                .font(HyperliteTypography.regular(11))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
            case .current, .partial:
                if snapshot.threads.isEmpty {
                    Text("No pinned Codex threads")
                        .font(HyperliteTypography.regular(11))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.threads) { thread in
                                HyperlitePinnedCodexThreadRow(thread: thread)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: 320)
                }
            }
        } else {
            ProgressView("Loading pinned Codex threads…")
                .controlSize(.small)
                .font(HyperliteTypography.regular(11))
        }
    }
}

private struct HyperlitePinnedCodexThreadRow: View {
    let thread: HyperlitePinnedCodexThread

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thread.displayTitle)
                .font(HyperliteTypography.medium(11))
                .foregroundStyle(
                    thread.metadataResolved
                        ? HyperliteTheme.secondaryText.color
                        : HyperliteTheme.mutedText.color
                )
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                if let directoryName = thread.directoryName {
                    Text(directoryName)
                }
                if !thread.metadataResolved {
                    Label("Metadata unavailable", systemImage: "questionmark.circle")
                }
            }
            .font(HyperliteTypography.regular(9))
            .foregroundStyle(HyperliteTheme.mutedText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [thread.displayTitle]
        if let directoryName = thread.directoryName { parts.append(directoryName) }
        if !thread.metadataResolved { parts.append("metadata unavailable") }
        return parts.joined(separator: ", ")
    }
}
