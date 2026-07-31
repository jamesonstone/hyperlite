import SwiftUI

struct HyperliteAttentionStatus: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("·")
                .foregroundStyle(HyperliteTheme.mutedText.color)
            if count == 0 {
                Label("All clear", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HyperliteTheme.green.color)
            } else {
                Label(
                    "\(count) need\(count == 1 ? "s" : "") attention",
                    systemImage: "exclamationmark.bubble.fill"
                )
                .foregroundStyle(HyperliteTheme.orange.color)
            }
        }
    }
}
