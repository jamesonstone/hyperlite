import AppKit
import SwiftUI

/// Shared controller for keyboard selection in the Open PRs list. The panel
/// publishes the current navigation items; the window installs a key monitor
/// that routes bare keys here whenever no palette or text field is focused.
@MainActor
final class HyperliteWorkspaceFocus: ObservableObject {
    static let shared = HyperliteWorkspaceFocus()

    @Published private(set) var selectionID: String?
    /// Whether to draw the selection highlight. Stays off until the operator
    /// presses a navigation key, so a fresh launch does not show a highlighted
    /// row that no one selected.
    @Published private(set) var focusVisible = false
    /// Asks the Open PRs list to bring the selection on screen.
    @Published private(set) var scrollRequest: HyperliteScrollRequest?
    /// The pull request row whose hover card is open from the keyboard.
    @Published private(set) var detailsID: String?

    private var items: [HyperliteWorkspaceNavItem] = []

    /// The panel reports its on-screen navigable entries here; the selection is
    /// reconciled so it always points at a still-visible item.
    func setItems(_ items: [HyperliteWorkspaceNavItem]) {
        self.items = items
        let reconciled = HyperliteWorkspaceNavigation.reconciledSelectionID(
            selectionID, ids: items.map(\.id)
        )
        if reconciled != selectionID { selectionID = reconciled }
    }

    /// Route a bare key press. Returns true when consumed so the monitor can
    /// swallow it. Defers to an open palette and to any focused text field,
    /// so typing is never intercepted.
    func handleKey(_ event: NSEvent) -> Bool {
        guard HyperliteState.shared.paletteMode == nil else { return false }
        guard event.modifierFlags
            .intersection([.command, .control, .option]).isEmpty
        else { return false }
        if editorIsFirstResponder(in: event.window) { return false }
        guard let command = HyperliteWorkspaceNavigation.command(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? ""
        ) else { return false }
        focusVisible = true
        switch command {
        case .next: move(by: 1)
        case .previous: move(by: -1)
        case .activate: activateSelection()
        case .toggleDetails: toggleDetails()
        case .dismissDetails: closeDetails()
        }
        return true
    }

    /// Space shows the selected pull request's card; Space again hides it.
    /// Headings have no card.
    private func toggleDetails() {
        guard let selectionID, selectionID.contains("\u{1F}") else { return }
        detailsID = detailsID == selectionID ? nil : selectionID
    }

    func closeDetails() {
        if detailsID != nil { detailsID = nil }
    }

    private func move(by delta: Int) {
        detailsID = nil
        selectionID = HyperliteWorkspaceNavigation.movedSelectionID(
            current: selectionID, ids: items.map(\.id), by: delta
        )
        requestScroll(centered: false)
    }

    /// Select one entry from outside the list (Command-P), highlight it, and
    /// center it so Return opens it next.
    func select(_ id: String) {
        selectionID = id
        focusVisible = true
        requestScroll(centered: true)
    }

    private func requestScroll(centered: Bool) {
        guard let selectionID else { return }
        scrollRequest = HyperliteScrollRequest(
            id: selectionID, centered: centered, token: (scrollRequest?.token ?? 0) + 1
        )
    }

    private func activateSelection() {
        guard let selectionID,
              let item = items.first(where: { $0.id == selectionID })
        else { return }
        switch item.action {
        case let .open(url):
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    private func editorIsFirstResponder(in window: NSWindow?) -> Bool {
        guard let responder = (window ?? NSApp.keyWindow)?.firstResponder
        else { return false }
        return responder is NSTextView || responder is NSText
    }
}
