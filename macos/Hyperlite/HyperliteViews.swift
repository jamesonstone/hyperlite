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
        Button("Refresh") { state.refresh() }
        Divider()
        Button("Settings…") { openHyperliteSettings() }
        Button("Quit Hyperlite") { NSApp.terminate(nil) }
    }
}

struct HyperliteWindow: View {
    @ObservedObject var state: HyperliteState
    let notepad: HyperliteNotepadState
    @State private var selectedThread: HyperliteThread?
    @State private var pendingProjectRemoval: HyperliteProjectLocation?

    private var activeThreads: [HyperliteThread] { state.activeThreads() }
    private var pullRequestScan: HyperliteProjectPullRequestScan? { state.pullRequestScan }
    private var configuredProjects: [HyperliteProjectLocation] {
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
                                        .foregroundStyle(.red)
                                }
                                if let pullRequests {
                                    HyperlitePullRequestPanel(scan: pullRequests)
                                } else {
                                    ProgressView("Loading open pull requests…")
                                        .controlSize(.small)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(height: sectionHeight)
                        .overlay(alignment: .bottom) { Divider() }

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                if state.scan == nil {
                                    ProgressView("Refreshing configured projects…")
                                        .controlSize(.small)
                                }
                                if projects.isEmpty, state.scan != nil {
                                    Text("No configured projects")
                                        .font(HyperliteTypography.regular(10))
                                        .foregroundStyle(.tertiary)
                                } else if !projects.isEmpty {
                                    HyperliteProjectMap(projects: projects)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(height: sectionHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)

            if let mode = state.paletteMode {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { state.dismissPalette() }
                HyperliteCommandPalette(
                    mode: mode,
                    threads: HyperliteFeatureFlags.inferredAttentionPresentation ? active : [],
                    projects: allProjects,
                    pullRequests: pullRequests,
                    onAction: handlePaletteAction,
                    onDismiss: state.dismissPalette
                )
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
            if HyperliteFeatureFlags.inferredAttentionPresentation {
                HStack(spacing: 6) {
                    HyperliteGhostMark()
                        .frame(width: 11, height: 11)
                    Text("\(active.count) active thread\(active.count == 1 ? "" : "s")")
                    HyperliteAttentionStatus(count: state.attentionThreadCount())
                }
                .font(HyperliteTypography.medium(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .tint(Color.orange.opacity(0.82))
                .disabled(state.isRefreshing || state.isUpdatingProjects)
                .help("Refresh projects and open pull requests (⌘R)")
            Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered)
                .help("Hyperlite settings")
        }
    }

    private var projectRemovalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingProjectRemoval != nil },
            set: { if !$0 { pendingProjectRemoval = nil } }
        )
    }

    private func handlePaletteAction(_ action: HyperlitePaletteAction) {
        if action == .chooseProjectToRemove {
            state.showPalette(.removeProjects)
            return
        }
        state.dismissPalette()
        switch action {
        case .refresh:
            state.refresh()
        case .settings:
            openHyperliteSettings()
        case .addProject:
            guard let path = HyperliteProjectPicker.selectProject() else { return }
            state.addProject(path: path)
        case .chooseProjectToRemove:
            break
        case let .removeProject(path):
            pendingProjectRemoval = configuredProjects.first { $0.path == path }
        case let .reveal(threadID):
            selectedThread = state.activeThreads().first { $0.id == threadID }
        case let .openPullRequest(rawURL):
            guard let url = URL(string: rawURL) else { return }
            NSWorkspace.shared.open(url)
        case let .revealPath(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
}
