import AppKit
import SwiftUI

struct HyperliteSectionHeader: View {
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

struct HyperliteEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No threads in flight")
                .font(.headline)
            Text("Hyperlite found no active coordination in the selected projects.")
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

    var body: some View {
        Form {
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

struct HyperliteThreadRow: View {
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
