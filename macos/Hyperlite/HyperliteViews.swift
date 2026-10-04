import AppKit
import SwiftUI

struct HyperliteWindow: View {
    @ObservedObject var state: HyperliteState
    @StateObject private var dashboardLists = HyperliteDashboardListState()
    @ObservedObject private var appearance = HyperliteAppearance.shared
    @ObservedObject private var focus = HyperliteWorkspaceFocus.shared
    @State var pendingProjectRemoval: HyperliteProjectLocation?
    @State var mergePromptCopied = false
    @State var mergePromptCopyGeneration = 0

    private var pullRequestScan: HyperliteProjectPullRequestScan? { state.pullRequestScan }

    var visibleOpenPullRequests: [HyperlitePullRequestRow] {
        guard let scan = pullRequestScan else { return [] }
        return HyperlitePullRequestPresentation.rows(scan: scan)
    }

    var body: some View {
        let pullRequests = pullRequestScan
        return ZStack(alignment: .topLeading) {
            pullRequestColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .environment(\.colorScheme, appearance.palette.colorScheme)

            if let mode = state.paletteMode {
                GeometryReader { paletteArea in
                    let paletteSize = HyperlitePaletteLayout.size(
                        containerWidth: paletteArea.size.width,
                        containerHeight: paletteArea.size.height
                    )
                    ZStack {
                        Color.primary.opacity(HyperliteTheme.colorScheme == .light ? 0.18 : 0.3)
                            .contentShape(Rectangle())
                            .onTapGesture { state.dismissPalette() }
                        HyperliteCommandPalette(
                            mode: mode,
                            projects: state.configuredProjects,
                            pullRequests: pullRequests,
                            visibleOpenPullRequestCount: visibleOpenPullRequests.count,
                            mergePromptCopied: mergePromptCopied,
                            onAction: handlePaletteAction,
                            onDismiss: state.dismissPalette
                        )
                        .frame(width: paletteSize.width, height: paletteSize.height)
                    }
                    .frame(width: paletteArea.size.width, height: paletteArea.size.height)
                }
                .id(mode)
            }
        }
        .frame(
            minWidth: HyperliteWorkspaceSizing.minWidth,
            minHeight: HyperliteWorkspaceSizing.minHeight
        )
        .task(id: mergePromptCopyGeneration) {
            guard mergePromptCopyGeneration > 0 else { return }
            mergePromptCopied = true
            do {
                try await Task.sleep(for: HyperliteOpenPRMergePrompt.confirmationDuration)
            } catch {
                return
            }
            mergePromptCopied = false
        }
        .background(HyperliteKeyCapture(onKeyDown: { focus.handleKey($0) }))
        .confirmationDialog(
            "Remove project from Hyperlite?",
            isPresented: projectRemovalConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Project", role: .destructive) {
                if let project = pendingProjectRemoval {
                    state.removeProject(path: project.path)
                }
                pendingProjectRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingProjectRemoval = nil }
        } message: {
            Text(
                "This removes \(pendingProjectRemoval?.name ?? "the project") from " +
                    "Hyperlite's configuration. It does not delete the repository or its worktrees."
            )
        }
    }

    @ViewBuilder
    private var pullRequestColumn: some View {
        if let pullRequests = pullRequestScan {
            HyperlitePullRequestPanel(
                scan: pullRequests,
                organization: dashboardLists,
                isRefreshing: state.isRefreshingPullRequests,
                isPollingActivity: state.isPollingActivity,
                errorMessage: state.errorMessage,
                selectionID: focus.focusVisible ? focus.selectionID : nil,
                scrollRequest: focus.scrollRequest,
                detailsID: focus.detailsID,
                onCloseDetails: { focus.closeDetails() },
                onNavItems: { focus.setItems($0) },
                onToggleIgnore: { state.toggleIgnored($0) }
            ) {
                windowActions
            }
            .environment(\.hyperliteWindowVisible, state.activityPolling.isWindowVisible)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if state.isRefreshingPullRequests {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(HyperliteOpenPRRefreshStatus.accessibilityRefreshing)
                    }
                    Spacer(minLength: 0)
                    windowActions
                }
                if let errorMessage = state.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HyperliteTypography.body)
                        .foregroundStyle(HyperliteTheme.red.color)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var windowActions: some View {
        HStack(alignment: .center, spacing: 6) {
            HyperliteGitHubRateLimitIndicator(rateLimit: pullRequestScan?.rateLimit)
            Button {
                do {
                    try HyperliteWorktreeSweep.start()
                } catch {
                    state.presentError(error.localizedDescription)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Open interactive git wt sweep in Terminal")
            Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .tint(HyperliteTheme.orange.color.opacity(0.82))
                .disabled(state.isRefreshingPullRequests || state.isUpdatingProjects)
                .help("Refresh open pull requests (⌘R)")
            Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered)
                .help("Settings")
        }
        .controlSize(.small)
    }
}
