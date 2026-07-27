import AppKit
import SwiftUI

struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        let count = state.items(maxAgeDays: maxAgeDays).count
        HStack(spacing: 2) {
            HyperliteGhostMark()
                .frame(width: 15, height: 15)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
        }
        .help("Hyperlite — \(count) item\(count == 1 ? "" : "s") require attention — \(hotkey)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hyperlite, \(count) items require attention")
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
    @State private var highlightedItemID: String?
    @State private var revealItemID: String?

    private var visibleItems: [HyperliteWorkItem] { state.items(maxAgeDays: maxAgeDays) }
    private var errors: [HyperliteDiagnostic] { state.scan?.errors ?? [] }
    private var warnings: [HyperliteDiagnostic] { state.scan?.warnings ?? [] }

    var body: some View {
        let items = visibleItems
        let currentErrors = errors
        let currentWarnings = warnings
        let activeProjectCount = Set(items.map(\.repositoryPath)).count
        return ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hyperlite").font(.system(size: 22, weight: .bold, design: .rounded))
                        HStack(spacing: 4) {
                            HyperliteGhostMark()
                                .frame(width: 12, height: 12)
                            Text("\(activeProjectCount) active project\(activeProjectCount == 1 ? "" : "s")")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                        .disabled(state.isRefreshing || state.isPruning)
                        .help("Refresh Git and pull request status")
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
                    ProgressView("Checking local work…")
                        .controlSize(.small)
                } else if items.isEmpty {
                    HyperliteEmptyState()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 7) {
                                ForEach(items) { item in
                                    HyperliteRow(
                                        item: item,
                                        highlighted: item.id == highlightedItemID
                                    )
                                    .id(item.id)
                                    if item.id != items.last?.id { Divider() }
                                }
                            }
                        }
                        .onChange(of: revealItemID) { itemID in
                            guard let itemID else { return }
                            proxy.scrollTo(itemID, anchor: .center)
                            revealItemID = nil
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
                    items: items,
                    errors: currentErrors,
                    warnings: currentWarnings,
                    onAction: handlePaletteAction,
                    onDismiss: state.dismissPalette
                )
                .id(mode)
            }
        }
        .frame(minWidth: 440, minHeight: 560)
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
        case .diagnostics:
            diagnosticsClickRequest += 1
        case let .prune(diagnostic):
            pendingPrune = diagnostic
        case let .reveal(itemID):
            highlightedItemID = itemID
            revealItemID = itemID
        }
    }
}

private struct HyperliteEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Nothing needs attention")
                .font(.headline)
            Text("No recent worktrees, main-branch changes, or pull requests.")
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
                Picker("Show recent work", selection: $maxAgeDays) {
                    ForEach(HyperlitePresentation.supportedAgeWindows, id: \.self) { days in
                        Text("Last \(days) days").tag(days)
                    }
                }
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

private struct HyperliteRow: View {
    let item: HyperliteWorkItem
    let highlighted: Bool

    var body: some View {
        Button(action: activate) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.statuses.first?.symbol ?? "circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color(for: item.statuses.first))
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.repository).font(.system(size: 16, weight: .bold))
                        Spacer(minLength: 8)
                        Text(HyperlitePresentation.ageLabel(for: item.updatedAt))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    HStack(spacing: 7) {
                        ForEach(item.statuses, id: \.self) { status in
                            Label(status.label, systemImage: status.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color(for: status))
                        }
                    }
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
        .help(description)
        .hyperliteHoverPopover { HyperliteItemHoverCard(item: item) }
    }

    private var description: String {
        let status = item.statuses.map(\.label).joined(separator: ", ")
        if item.pullRequest != nil { return "\(status). Click to open the pull request in your browser." }
        return "\(status). Click to copy \(item.clickPath)."
    }

    private func activate() {
        if let urlString = item.pullRequest?.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.clickPath, forType: .string)
    }

    private func color(for status: HyperliteStatus?) -> Color {
        switch status {
        case .pullRequest: .pink
        case .worktree: .cyan
        case .unstaged: .red
        case nil: .secondary
        }
    }
}
