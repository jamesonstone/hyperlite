import AppKit
import SwiftUI

struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        let count = state.attentionThreadCount(maxAgeDays: maxAgeDays)
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
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10
    @State private var diagnosticsClickRequest = 0
    @State private var pendingPrune: HyperliteDiagnostic?
    @State private var selectedThread: HyperliteThread?
    @State private var highlightedThreadID: String?
    @State private var revealThreadID: String?
    @State private var highlightClearTask: Task<Void, Never>?

    private var visibleThreads: [HyperliteThread] { state.visibleThreads(maxAgeDays: maxAgeDays) }
    private var errors: [HyperliteDiagnostic] { state.scan?.errors ?? [] }
    private var warnings: [HyperliteDiagnostic] { state.scan?.warnings ?? [] }

    var body: some View {
        let threads = visibleThreads
        let currentErrors = errors
        let currentWarnings = warnings
        let activeCount = threads.filter(\.active).count
        return ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hyperlite").font(.system(size: 22, weight: .bold, design: .rounded))
                        HStack(spacing: 4) {
                            HyperliteGhostMark()
                                .frame(width: 12, height: 12)
                            Text("\(activeCount) thread\(activeCount == 1 ? "" : "s") in flight")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                        .disabled(state.isRefreshing || state.isPruning)
                        .help("Refresh evidence and inferred threads")
                    if !currentErrors.isEmpty || !currentWarnings.isEmpty {
                        HyperliteDiagnosticsButton(
                            errors: currentErrors,
                            warnings: currentWarnings,
                            isPruning: state.isPruning,
                            clickRequest: diagnosticsClickRequest,
                            onPruneRequest: { pendingPrune = $0 }
                        )
                    }
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
                } else if threads.isEmpty {
                    HyperliteEmptyState()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(HyperliteThreadSection.allCases, id: \.rawValue) { section in
                                    let sectionThreads = state.threads(section: section, maxAgeDays: maxAgeDays)
                                    if !sectionThreads.isEmpty {
                                        HyperliteSectionHeader(section: section, count: sectionThreads.count)
                                        ForEach(sectionThreads) { thread in
                                            HyperliteThreadRow(
                                                thread: thread,
                                                highlighted: thread.id == highlightedThreadID,
                                                onOpen: { selectedThread = thread }
                                            )
                                            .id(thread.id)
                                            if thread.id != sectionThreads.last?.id { Divider() }
                                        }
                                    }
                                }
                            }
                        }
                        .onChange(of: revealThreadID) { threadID in
                            guard let threadID else { return }
                            proxy.scrollTo(threadID, anchor: .center)
                            scheduleHighlightClear(for: threadID)
                            revealThreadID = nil
                        }
                    }
                }
            }
            .padding(20)

            if let mode = state.paletteMode {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { state.dismissPalette() }
                HyperliteCommandPalette(
                    mode: mode,
                    threads: threads,
                    errors: currentErrors,
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
        .onDisappear {
            highlightClearTask?.cancel()
            highlightClearTask = nil
            highlightedThreadID = nil
            revealThreadID = nil
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
        case .diagnostics:
            diagnosticsClickRequest += 1
        case let .prune(diagnostic):
            pendingPrune = diagnostic
        case let .reveal(threadID):
            highlightClearTask?.cancel()
            highlightClearTask = nil
            highlightedThreadID = threadID
            revealThreadID = threadID
        }
    }

    private func scheduleHighlightClear(for threadID: String) {
        highlightClearTask?.cancel()
        highlightClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, highlightedThreadID == threadID else { return }
            highlightedThreadID = nil
        }
    }
}
