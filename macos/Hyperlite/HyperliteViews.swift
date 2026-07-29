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
        .accessibilityLabel("Hyperlite, \(count) thread\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention")
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
    @State private var pendingPrune: HyperliteDiagnostic?
    @State private var selectedThread: HyperliteThread?

    private var activeThreads: [HyperliteThread] { state.activeThreads() }
    private var pullRequestScan: HyperliteProjectPullRequestScan? { state.pullRequestScan }
    private var projectIndex: [HyperliteProjectLocation] {
        HyperliteProjectIndexPresentation.visibleProjects(
            state.scan?.projectIndex ?? [],
            pullRequests: pullRequestScan
        )
    }
    private var warnings: [HyperliteDiagnostic] { state.scan?.warnings ?? [] }

    var body: some View {
        let active = activeThreads
        let pullRequests = pullRequestScan
        let projects = projectIndex
        let currentWarnings = warnings
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Hyperlite")
                        .font(HyperliteTypography.bold(22))
                        .fixedSize(horizontal: true, vertical: false)
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
                        .disabled(state.isRefreshing || state.isPruning)
                        .help("Refresh projects and open pull requests")
                    Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                        .buttonStyle(.bordered)
                        .help("Hyperlite settings")
                }

                HyperliteNotepadView(state: notepad)

                if let errorMessage = state.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HyperliteTypography.regular(12))
                        .foregroundStyle(.red)
                }
                if state.scan == nil {
                    ProgressView("Refreshing configured projects…")
                        .controlSize(.small)
                }
                if let pullRequests {
                    HyperlitePullRequestPanel(scan: pullRequests)
                        .layoutPriority(1)
                } else {
                    ProgressView("Loading open pull requests…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if !projects.isEmpty {
                    HyperliteProjectMap(projects: projects)
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
                    warnings: currentWarnings,
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
            "Prune stale worktree metadata?",
            isPresented: pruneConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Prune All Stale Metadata", role: .destructive) {
                if let pendingPrune { state.prune(pendingPrune) }
                pendingPrune = nil
            }
            Button("Cancel", role: .cancel) { pendingPrune = nil }
        } message: {
            Text("Git will prune all stale worktree records for \(pendingPrune?.repository ?? "this repository") after re-verifying the selected path.")
        }
    }

    private var pruneConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingPrune != nil },
            set: { if !$0 { pendingPrune = nil } }
        )
    }

    private func handlePaletteAction(_ action: HyperlitePaletteAction) {
        state.dismissPalette()
        switch action {
        case .refresh:
            state.refresh()
        case .settings:
            openHyperliteSettings()
        case let .prune(diagnostic):
            pendingPrune = diagnostic
        case let .reveal(threadID):
            selectedThread = state.activeThreads().first { $0.id == threadID }
        }
    }
}
