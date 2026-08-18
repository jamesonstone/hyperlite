import AppKit
import SwiftUI

struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        Group {
            if HyperliteFeatureFlags.inferredAttentionPresentation {
                attentionLabel
            } else {
                HyperliteGhostMark()
                    .frame(width: 15, height: 15)
                    .help("Hyperlite — \(hotkey)")
                    .accessibilityLabel("Hyperlite")
            }
        }
    }

    private var attentionLabel: some View {
        let count = state.attentionThreadCount()
        return HStack(spacing: 2) {
            HyperliteGhostMark()
                .frame(width: 15, height: 15)
            Text(count > 99 ? "99+" : "\(count)")
                .font(HyperliteTypography.bold(10).monospacedDigit())
        }
        .help("Hyperlite — \(count) thread\(count == 1 ? "" : "s") need attention — \(hotkey)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Hyperlite, \(count) thread\(count == 1 ? "" : "s") " +
                "need\(count == 1 ? "s" : "") attention"
        )
    }
}

struct HyperliteMenu: View {
    @ObservedObject var state: HyperliteState

    var body: some View {
        Button("Open Hyperlite") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Hyperlite" })?.makeKeyAndOrderFront(nil)
        }
        Button("Refresh") { state.refreshAll() }
        Divider()
        Button("Settings…") { openHyperliteSettings() }
        Button("Quit Hyperlite") { NSApp.terminate(nil) }
    }
}

struct HyperliteWindow: View {
    @ObservedObject var state: HyperliteState
    @ObservedObject var pinnedCodexThreads: HyperlitePinnedCodexThreadState
    @ObservedObject var pinboard: HyperlitePinboardState
    @ObservedObject var agentSessions: HyperliteAgentSessionState
    let notepad: HyperliteNotepadState
    @StateObject private var dashboardLists = HyperliteDashboardListState()
    @State var selectedThread: HyperliteThread?
    @State var pendingProjectRemoval: HyperliteProjectLocation?

    private var activeThreads: [HyperliteThread] { state.activeThreads() }
    private var pullRequestScan: HyperliteProjectPullRequestScan? { state.pullRequestScan }
    var configuredProjects: [HyperliteProjectLocation] {
        HyperliteProjectIndexPresentation.configuredProjects(
            state.scan?.projectIndex ?? [],
            pullRequests: pullRequestScan
        )
    }
    private var visibleProjects: [HyperliteProjectLocation] {
        HyperliteProjectIndexPresentation.visibleProjects(
            state.scan?.projectIndex ?? [],
            pullRequests: pullRequestScan
        )
    }

    var body: some View {
        let active = activeThreads
        let pullRequests = pullRequestScan
        let allProjects = configuredProjects
        let projects = visibleProjects
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                header(active: active)

                GeometryReader { workspace in
                    if state.workspace == .dashboard {
                        let sectionHeight = HyperliteWorkspaceSizing.sectionHeight(
                            availableHeight: workspace.size.height
                        )
                        VStack(alignment: .leading, spacing: HyperliteWorkspaceSizing.sectionSpacing) {
                            HyperliteNotepadView(state: notepad)
                                .frame(height: sectionHeight)
                                .clipped()

                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let errorMessage = state.errorMessage {
                                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                            .font(HyperliteTypography.regular(12))
                                            .foregroundStyle(HyperliteTheme.red.color)
                                    }
                                    if let pullRequests {
                                        HyperlitePullRequestPanel(
                                            scan: pullRequests,
                                            organization: dashboardLists
                                        )
                                    } else {
                                        ProgressView("Loading open pull requests…")
                                            .controlSize(.small)
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(height: sectionHeight)
                            .overlay(alignment: .bottom) { HyperliteThemeDivider() }

                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if state.scan == nil {
                                        ProgressView("Refreshing configured projects…")
                                            .controlSize(.small)
                                    }
                                    if projects.isEmpty, state.scan != nil {
                                        Text("No configured projects")
                                            .font(HyperliteTypography.regular(10))
                                            .foregroundStyle(HyperliteTheme.mutedText.color)
                                    } else if !projects.isEmpty {
                                        HyperliteProjectMap(
                                            projects: projects,
                                            pullRequests: pullRequests,
                                            organization: dashboardLists
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(height: sectionHeight)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if state.workspace == .pinboard {
                        HyperlitePinboardView(state: pinboard)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        HyperliteAgentSessionsWorkspace(state: agentSessions)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)

            if let mode = state.paletteMode {
                let paletteProjects = mode == .removeProjects
                    ? (state.scan?.projectIndex ?? [])
                    : allProjects
                GeometryReader { paletteArea in
                    let paletteSize = HyperlitePaletteLayout.size(
                        containerWidth: paletteArea.size.width,
                        containerHeight: paletteArea.size.height
                    )
                    ZStack {
                        Color.black.opacity(0.3)
                            .contentShape(Rectangle())
                            .onTapGesture { state.dismissPalette() }
                        HyperliteCommandPalette(
                            mode: mode,
                            threads: HyperliteFeatureFlags.inferredAttentionPresentation ? active : [],
                            projects: paletteProjects,
                            pullRequests: pullRequests,
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
        .sheet(item: $selectedThread) { thread in
            HyperliteThreadDetail(
                thread: thread,
                onSeen: { state.markSeen(threadID: thread.id) },
                onSaveNote: { state.updateNote(threadID: thread.id, note: $0) }
            )
            .hyperliteTheme()
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

    private func header(active: [HyperliteThread]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 7) {
                Text("Hyperlite")
                    .font(HyperliteTypography.bold(22))
                    .fixedSize(horizontal: true, vertical: false)
                Text("👻")
                    .font(.system(size: 18))
                    .accessibilityLabel("Ghost")
            }
            HyperliteWorkspaceControl(workspace: state.workspace, onSelect: state.showWorkspace)
            if HyperliteFeatureFlags.inferredAttentionPresentation {
                HStack(spacing: 6) {
                    HyperliteGhostMark()
                        .frame(width: 11, height: 11)
                    Text("\(active.count) active thread\(active.count == 1 ? "" : "s")")
                    HyperliteAttentionStatus(count: state.attentionThreadCount())
                }
                .font(HyperliteTypography.medium(11))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            HyperlitePinnedCodexThreadIndicator(state: pinnedCodexThreads)
            HyperliteGitHubRateLimitIndicator(rateLimit: pullRequestScan?.rateLimit)
            Button { state.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .tint(HyperliteTheme.orange.color.opacity(0.82))
                .disabled(state.isRefreshing || state.isUpdatingProjects)
                .help("Refresh projects, open pull requests, and pinned Codex threads (⌘R)")
            Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered)
                .help("Hyperlite settings")
        }
    }

}
