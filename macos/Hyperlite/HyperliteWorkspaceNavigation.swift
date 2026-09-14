import Foundation

/// One keyboard-navigable entry in the Open PRs pane. The panel builds these in
/// render order (pinned rows, visible project headings and their rows, the
/// quiet-ones toggle, and expanded hidden headings) so selection movement and
/// activation stay in lockstep with what is on screen.
struct HyperliteWorkspaceNavItem: Equatable, Identifiable {
    let id: String
    let action: HyperliteWorkspaceNavAction

    init(id: String, action: HyperliteWorkspaceNavAction) {
        self.id = id
        self.action = action
    }
}

enum HyperliteWorkspaceNavAction: Equatable {
    /// Open a pull request or repository on GitHub. A `nil` URL is a no-op so a
    /// heading without a resolvable GitHub target still occupies a slot.
    case open(URL?)
    /// Toggle the `watching the quiet ones` disclosure.
    case toggleQuietOnes
}

/// The command a bare (unmodified) key press maps to while the Open PRs pane
/// owns focus. `j`/`k` mirror the arrow keys the way the command palette
/// already treats them.
enum HyperliteWorkspaceNavCommand: Equatable {
    case next
    case previous
    case activate
}

/// Pure navigation math for the Open PRs pane, free of AppKit and SwiftUI so it
/// is covered by the executable model tests.
enum HyperliteWorkspaceNavigation {
    static let quietOnesID = "quiet-ones"

    static func headerID(sectionID: String) -> String { "header:\(sectionID)" }

    /// Classify a bare key press. Callers must first confirm no command,
    /// control, or option modifier is held (those belong to menu shortcuts).
    static func command(keyCode: UInt16, characters: String) -> HyperliteWorkspaceNavCommand? {
        switch keyCode {
        case 125: return .next // down arrow
        case 126: return .previous // up arrow
        case 36, 76: return .activate // return, keypad enter
        default: break
        }
        switch characters.lowercased() {
        case "j": return .next
        case "k": return .previous
        default: return nil
        }
    }

    /// The id one step from `current` in `ids`, clamped at the ends. A missing
    /// or absent current selection starts at the first item so the first key
    /// press always lands somewhere visible.
    static func movedSelectionID(current: String?, ids: [String], by delta: Int) -> String? {
        guard let first = ids.first else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return first }
        let next = min(max(index + delta, 0), ids.count - 1)
        return ids[next]
    }

    /// Keep a selection valid as the visible items change: preserve it when it
    /// still exists, otherwise clear it so the focus highlight disappears
    /// instead of jumping to an unrelated item. A first key press re-selects the
    /// first item via `movedSelectionID`.
    static func reconciledSelectionID(_ current: String?, ids: [String]) -> String? {
        guard let current, ids.contains(current) else { return nil }
        return current
    }
}
