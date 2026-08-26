import SwiftUI

enum HyperlitePaletteChrome {
    static func title(for mode: HyperlitePaletteMode) -> String {
        switch mode {
        case .commands: "Commands"
        case .projects: "Projects"
        case .removeProjects: "Remove Project"
        }
    }

    static func symbol(for mode: HyperlitePaletteMode) -> String {
        mode == .commands ? "command" : "folder"
    }

    static func shortcut(for mode: HyperlitePaletteMode) -> String {
        switch mode {
        case .commands, .removeProjects: "⌘K"
        case .projects: "⌘P"
        }
    }

    static func searchPrompt(for mode: HyperlitePaletteMode) -> String {
        switch mode {
        case .commands: "Search commands and notes"
        case .projects: "Search projects, PRs, and worktrees"
        case .removeProjects: "Search configured projects"
        }
    }
}

enum HyperlitePaletteLayout {
    static let maximumWidth: CGFloat = 560
    static let maximumHeight: CGFloat = 480
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 48

    static func size(containerWidth: CGFloat, containerHeight: CGFloat) -> CGSize {
        CGSize(
            width: min(maximumWidth, max(0, containerWidth - (horizontalInset * 2))),
            height: min(maximumHeight, max(0, containerHeight - (verticalInset * 2)))
        )
    }
}
