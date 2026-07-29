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

struct HyperliteQuietStatus: View {
    let activeCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 26, height: 26)
                .background(Color.cyan.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing needs your attention")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cyan.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.12), lineWidth: 1)
        }
    }

    private var message: String {
        guard activeCount > 0 else {
            return "There is no current coordination work."
        }
        return "Active work is available for context; no decision or intervention is requested."
    }
}

struct HyperliteActivitySection: View {
    let threads: [HyperliteThread]
    let onOpen: (HyperliteThread) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Ongoing activity")
                    .font(.caption.weight(.bold))
                Text("\(threads.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Informational", systemImage: "info.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(threads) { thread in
                    HyperliteActivityCard(thread: thread) {
                        onOpen(thread)
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}

struct HyperliteActivityCard: View {
    let thread: HyperliteThread
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: thread.phase.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .frame(width: 22, height: 22)
                        .background(Color.cyan.opacity(0.10), in: Circle())
                    Text(thread.projectName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(HyperlitePresentation.ageLabel(for: thread.updatedAt))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(thread.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Label(thread.phase.label, systemImage: "circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open this active thread. No attention is currently requested.")
        .hyperliteHoverPopover { HyperliteThreadHoverCard(thread: thread) }
    }

    private var summary: String? {
        thread.goal.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let label = line.trimmingCharacters(in: CharacterSet(charactersIn: "#: ")).lowercased()
                return label != "original ask" && line.count >= 20
            }
    }
}
