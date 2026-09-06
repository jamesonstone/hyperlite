import AppKit
import SwiftUI

struct HyperliteWindow: View {
    @ObservedObject var state: HyperliteState
    let notepad: HyperliteNotepadState
    @StateObject private var dashboardLists = HyperliteDashboardListState()
    @StateObject private var pullRequestPins = HyperlitePullRequestPinStore()
    @ObservedObject private var appearance = HyperliteAppearance.shared
    @State var pendingProjectRemoval: HyperliteProjectLocation?
    @State var mergePromptCopied = false
    @State var mergePromptCopyGeneration = 0

    private var pullRequestScan: HyperliteProjectPullRequestScan? { state.pullRequestScan }

    var visibleOpenPullRequests: [HyperlitePullRequestRow] {
        guard let scan = pullRequestScan else { return [] }
        let sections = pullRequestPins.sections(
            for: HyperlitePullRequestPresentation.rows(scan: scan)
        )
        return sections.pinned + sections.unpinned
    }

    var body: some View {
        let pullRequests = pullRequestScan
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: HyperliteWorkspaceSizing.sectionSpacing) {
                header

                HyperliteNotepadView(state: notepad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let errorMessage = state.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(HyperliteTypography.body)
                                .foregroundStyle(HyperliteTheme.red.color)
                        } else if let statusMessage = state.statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle")
                                .font(HyperliteTypography.body)
                                .foregroundStyle(HyperliteTheme.secondaryText.color)
                        }
                        if let pullRequests {
                            HyperlitePullRequestPanel(
                                scan: pullRequests,
                                organization: dashboardLists,
                                pins: pullRequestPins
                            )
                        } else {
                            ProgressView("Loading open pull requests…")
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                            notepad: notepad,
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
        .frame(minWidth: 480, minHeight: 580)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer(minLength: 0)
            HyperliteGitHubRateLimitIndicator(rateLimit: pullRequestScan?.rateLimit)
            Button { state.updateDefaultBranches() } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(state.isRefreshing || state.isUpdatingProjects)
            .help("Fast-forward configured default branches")
            Button {
                do {
                    try HyperliteGitMaintenance.startSweep()
                } catch {
                    state.presentError(error.localizedDescription)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Open interactive git wt sweep in Terminal")
            Button { state.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .tint(HyperliteTheme.orange.color.opacity(0.82))
                .disabled(state.isRefreshing || state.isUpdatingProjects)
                .help("Refresh open pull requests (⌘R)")
            Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered)
                .help("Settings")
        }
    }
}
