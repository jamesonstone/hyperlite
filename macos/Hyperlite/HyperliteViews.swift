import AppKit
import SwiftUI

struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        let count = state.attentionThreadCount()
        HStack(spacing: 2) {
            HyperliteGhostMark()
                .frame(width: 15, height: 15)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
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
    @State private var pendingPrune: HyperliteDiagnostic?
    @State private var selectedThread: HyperliteThread?

    private var activeThreads: [HyperliteThread] { state.activeThreads() }
    private var attentionThreads: [HyperliteThread] { state.attentionThreads() }
    private var informationalThreads: [HyperliteThread] {
        guard let scan = state.scan else { return [] }
        return HyperlitePresentation.informationalThreads(scan: scan)
    }
    private var warnings: [HyperliteDiagnostic] { state.scan?.warnings ?? [] }

    var body: some View {
        let attention = attentionThreads
        let active = activeThreads
        let informational = informationalThreads
        let currentWarnings = warnings
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hyperlite").font(.system(size: 22, weight: .bold, design: .rounded))
                        HStack(spacing: 6) {
                            HyperliteGhostMark()
                                .frame(width: 12, height: 12)
                            Text("\(active.count) active thread\(active.count == 1 ? "" : "s")")
                            HyperliteAttentionStatus(count: attention.count)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                        .disabled(state.isRefreshing || state.isPruning)
                        .help("Refresh evidence and inferred threads")
                    Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                        .buttonStyle(.bordered)
                        .help("Hyperlite settings")
                }

                if let errorMessage = state.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                if state.scan == nil {
                    ProgressView("Reconstructing local threads…")
                        .controlSize(.small)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if attention.isEmpty {
                                HyperliteQuietStatus(activeCount: active.count)
                            } else {
                                HyperliteSectionHeader(count: attention.count)
                                ForEach(attention) { thread in
                                    HyperliteThreadRow(
                                        thread: thread,
                                        highlighted: false,
                                        onOpen: { selectedThread = thread }
                                    )
                                    if thread.id != attention.last?.id {
                                        Divider()
                                    }
                                }
                            }

                            if !informational.isEmpty {
                                HyperliteActivitySection(
                                    threads: informational,
                                    onOpen: { selectedThread = $0 }
                                )
                            }
                        }
                        .padding(.bottom, 8)
                    }
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
                    threads: active,
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
