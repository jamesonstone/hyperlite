import AppKit
import SwiftUI

struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        let count = state.attentionProjectCount(maxAgeDays: maxAgeDays)
        HStack(spacing: 2) {
            Text("🚀")
            Text("✦ \(count > 99 ? "99+" : "\(count)")")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .help("Hyperlite — \(count) project\(count == 1 ? "" : "s") need attention — \(hotkey)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hyperlite, \(count) projects need attention")
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

    private var visibleItems: [HyperliteWorkItem] { state.items(maxAgeDays: maxAgeDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hyperlite").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("🚀 \(state.attentionProjectCount(maxAgeDays: maxAgeDays)) active project\(state.attentionProjectCount(maxAgeDays: maxAgeDays) == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .disabled(state.isRefreshing)
                    .help("Refresh Git and pull request status")
                Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                    .buttonStyle(.bordered)
                    .help("Hyperlite settings")
            }

            if let errorMessage = state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if state.scan == nil {
                ProgressView("Checking local work…")
                    .controlSize(.small)
            } else if let scan = state.scan {
                if !scan.errors.isEmpty || !scan.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(partialScanSummary(for: scan), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(scan.errors.isEmpty ? .orange : .red)
                        ForEach(scan.errors.indices, id: \.self) { index in
                            Text("Error: \(diagnosticDescription(scan.errors[index]))")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        ForEach(scan.warnings.indices, id: \.self) { index in
                            Text("Warning: \(diagnosticDescription(scan.warnings[index]))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if visibleItems.isEmpty {
                    HyperliteEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(visibleItems) { item in
                                HyperliteRow(item: item)
                                if item.id != visibleItems.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 560)
    }

    private func partialScanSummary(for scan: HyperliteWorkScan) -> String {
        var diagnostics: [String] = []
        if !scan.errors.isEmpty {
            diagnostics.append("\(scan.errors.count) error\(scan.errors.count == 1 ? "" : "s")")
        }
        if !scan.warnings.isEmpty {
            diagnostics.append("\(scan.warnings.count) warning\(scan.warnings.count == 1 ? "" : "s")")
        }
        return "Partial scan: \(diagnostics.joined(separator: " and ")). Results may be incomplete."
    }

    private func diagnosticDescription(_ diagnostic: HyperliteDiagnostic) -> String {
        "\(diagnostic.repository) (\(diagnostic.stage)): \(diagnostic.message)"
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
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
