import SwiftUI

struct HyperliteAttentionStatus: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("·")
                .foregroundStyle(.tertiary)
            if count == 0 {
                Label("All clear", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.cyan)
            } else {
                Label(
                    "\(count) need\(count == 1 ? "s" : "") attention",
                    systemImage: "exclamationmark.bubble.fill"
                )
                .foregroundStyle(.orange)
            }
        }
    }
}

struct HyperliteActivityLedger: View {
    let threads: [HyperliteThread]
    let title: String
    let onOpen: (HyperliteThread) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 360), spacing: 24, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(threads.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("For reference")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(threads) { thread in
                    HyperliteActivityRow(thread: thread) {
                        onOpen(thread)
                    }
                }
            }
        }
    }
}

struct HyperliteActivityRow: View {
    let thread: HyperliteThread
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.projectName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 68, alignment: .leading)
                Text(thread.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(thread.phase.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(HyperlitePresentation.ageLabel(for: thread.updatedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.055))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("Open this active thread. No attention is currently requested.")
        .hyperliteHoverPopover { HyperliteThreadHoverCard(thread: thread) }
    }
}
