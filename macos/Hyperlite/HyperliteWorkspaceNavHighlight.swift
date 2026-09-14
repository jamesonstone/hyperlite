import SwiftUI

/// A rounded highlight that marks the keyboard-selected Open PRs entry. Kept as
/// a shared modifier so the same treatment covers pull-request rows, project
/// headings, and the quiet-ones toggle, and so the selection reads clearly as
/// "focus is here" against the flat list chrome.
struct HyperliteWorkspaceNavHighlight: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                selected
                    ? HyperliteTheme.blue.color.opacity(0.24)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(HyperliteTheme.cyan.color.opacity(0.8), lineWidth: 1)
                }
            }
    }
}

extension View {
    func hyperliteNavHighlight(selected: Bool) -> some View {
        modifier(HyperliteWorkspaceNavHighlight(selected: selected))
    }
}
