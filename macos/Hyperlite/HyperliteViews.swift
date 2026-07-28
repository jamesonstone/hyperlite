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
        .accessibilityLabel("Hyperlite, \(count) threads need attention")
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
                onSeen: { state.markSeen(thread) },
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

private struct HyperliteSectionHeader: View {
    let section: HyperliteThreadSection
    let count: Int

    var body: some View {
        HStack {
            Text(section.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(section == .attention ? Color.orange : Color.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 5)
    }
}

private struct HyperliteEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No threads in flight")
                .font(.headline)
            Text("Hyperlite found no active goals or recent completed work in the selected projects.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct HyperliteSettingsView: View {
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10

    var body: some View {
        Form {
            Section("Display") {
                Picker("Show completed threads", selection: $maxAgeDays) {
                    ForEach(HyperlitePresentation.supportedAgeWindows, id: \.self) { days in
                        Text("Last \(days) days").tag(days)
                    }
                }
                Text("Active threads remain visible regardless of age.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                TextField("Hot key", text: $hotkey)
                Text("Default: \(defaultHotKey). Use modifier names joined with +, for example Command+Shift+H.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Quit Hyperlite") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}

private struct HyperliteThreadRow: View {
    let thread: HyperliteThread
    let highlighted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: thread.hasUnseenAttention ? "exclamationmark.bubble.fill" : thread.phase.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(thread.hasUnseenAttention ? .orange : .cyan)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(thread.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(HyperlitePresentation.ageLabel(for: thread.updatedAt))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Text(thread.projectName)
                        Text("·")
                        Label(thread.phase.label, systemImage: thread.phase.symbol)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(thread.whyNow)
                        .font(.subheadline)
                        .foregroundStyle(thread.hasUnseenAttention ? .primary : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                highlighted ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .help("Open the inferred thread and its supporting evidence.")
        .hyperliteHoverPopover { HyperliteThreadHoverCard(thread: thread) }
    }
}

private struct HyperliteThreadDetail: View {
    let thread: HyperliteThread
    let onSeen: () -> Void
    let onSaveNote: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(thread: HyperliteThread, onSeen: @escaping () -> Void, onSaveNote: @escaping (String) -> Void) {
        self.thread = thread
        self.onSeen = onSeen
        self.onSaveNote = onSaveNote
        _note = State(initialValue: thread.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title).font(.title2.bold())
                    Label(thread.phase.label, systemImage: thread.phase.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailSection("Goal", thread.goal)
                    detailSection("Why now", thread.whyNow)
                    detailSection("Rationale", thread.rationale)
                    detailSection("Progress", progressSummary)
                    if !thread.dependencies.isEmpty {
                        bulletSection("Dependencies and order", thread.dependencies.map {
                            "\($0.kind.replacingOccurrences(of: "_", with: " ")): \($0.targetThreadID ?? $0.target) [\($0.basis)]"
                        })
                    }
                    if !thread.implications.isEmpty {
                        bulletSection("Implications", thread.implications.map {
                            "\($0.summary) [\($0.basis)]"
                        })
                    }
                    bulletSection(
                        "Remaining obligations",
                        thread.remainingObligations.map(\.summary),
                        empty: "No remaining obligation is established by current evidence."
                    )
                    evidenceSection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(.headline)
                        TextEditor(text: $note)
                            .font(.body)
                            .frame(minHeight: 72)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.25))
                            }
                        HStack {
                            Text("Optional annotation; it never creates or completes a thread.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Save Note") { onSaveNote(note) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 620)
        .onAppear(perform: onSeen)
    }

    private var progressSummary: String {
        let artifactSummary = thread.artifacts.map {
            "\($0.kind.replacingOccurrences(of: "_", with: " ")) \($0.state)"
        }.joined(separator: ", ")
        return artifactSummary.isEmpty ? "No active artifact evidence." : artifactSummary
    }

    @ViewBuilder
    private func detailSection(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, _ values: [String], empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if values.isEmpty, let empty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text("• \(value)").textSelection(.enabled)
                }
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence").font(.headline)
            ForEach(thread.evidence) { evidence in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evidence.title).font(.subheadline.weight(.semibold))
                        Text("\(evidence.source) · \(evidence.freshness)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let value = evidence.url, let url = URL(string: value) {
                        Link("Open", destination: url)
                    } else if let path = evidence.path {
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    }
                }
            }
        }
    }
}
