import AppKit
import SwiftUI

struct HyperliteSectionHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Attention")
                .font(HyperliteTypography.bold(11))
                .foregroundStyle(Color.orange)
            Text("\(count)")
                .font(HyperliteTypography.bold(10).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 5)
    }
}

struct HyperliteSettingsView: View {
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        Form {
            Section("Shortcut") {
                TextField("Hot key", text: $hotkey)
                Text("Default: \(defaultHotKey). Use modifier names joined with +, for example Command+Shift+H.")
                    .font(HyperliteTypography.regular(11))
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

struct HyperliteThreadRow: View {
    let thread: HyperliteThread
    let highlighted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: thread.hasUnseenAttention ? "exclamationmark.bubble.fill" : thread.phase.symbol)
                    .font(HyperliteTypography.bold(18))
                    .foregroundStyle(thread.hasUnseenAttention ? .orange : .cyan)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(thread.title)
                            .font(HyperliteTypography.bold(15))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(HyperlitePresentation.ageLabel(for: thread.updatedAt))
                            .font(HyperliteTypography.semibold(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Text(thread.projectName)
                        Text("·")
                        Label(thread.phase.label, systemImage: thread.phase.symbol)
                    }
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(.secondary)
                    if let summary = HyperlitePresentation.rowSummary(for: thread) {
                        Text(summary)
                            .font(HyperliteTypography.regular(12))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
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
        .help("Open the inferred thread and its supporting evidence.")
        .hyperliteHoverPopover { HyperliteThreadHoverCard(thread: thread) }
    }
}
