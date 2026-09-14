import AppKit
import SwiftUI

/// Shared controller for keyboard focus in the workspace. It owns which pane
/// (Open PRs or Notes) is active and, within Open PRs, which entry is selected.
/// The panel publishes the current navigation items; the window installs a key
/// monitor that routes bare keys here, and the Navigate menu routes ⌘1/⌘2 here.
@MainActor
final class HyperliteWorkspaceFocus: ObservableObject {
    static let shared = HyperliteWorkspaceFocus()

    enum Pane: Equatable {
        case pullRequests
        case notes
    }

    @Published private(set) var pane: Pane = .pullRequests
    @Published private(set) var selectionID: String?
    /// Whether to draw focus chrome. Stays off until the operator engages the
    /// keyboard (⌘1/⌘2 or a navigation key), so a fresh launch is not covered in
    /// a ring and a highlighted row that no one selected.
    @Published private(set) var focusVisible = false

    private var items: [HyperliteWorkspaceNavItem] = []

    /// Wired by the window so the controller can reveal and focus each pane
    /// without importing their view state.
    var revealPullRequests: (() -> Void)?
    var focusNotesEditor: (() -> Void)?

    /// The panel reports its on-screen navigable entries here; the selection is
    /// reconciled so it always points at a still-visible item.
    func setItems(_ items: [HyperliteWorkspaceNavItem]) {
        self.items = items
        let reconciled = HyperliteWorkspaceNavigation.reconciledSelectionID(
            selectionID, ids: items.map(\.id)
        )
        if reconciled != selectionID { selectionID = reconciled }
    }

    /// ⌘1: reveal Open PRs, resign the Notes editor so `j`/`k` navigate instead
    /// of typing, and land the selection on the first entry when unset.
    func focusPullRequests() {
        revealPullRequests?()
        pane = .pullRequests
        focusVisible = true
        NSApp.keyWindow?.makeFirstResponder(nil)
        if selectionID == nil { selectionID = items.first?.id }
    }

    /// ⌘2: focus the active Notes editor.
    func focusNotes() {
        pane = .notes
        focusVisible = true
        focusNotesEditor?()
    }

    /// Route a bare key press. Returns true when consumed so the monitor can
    /// swallow it. Defers to an open palette and to the Notes editor's first
    /// responder, so typing is never intercepted.
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
        pane = .pullRequests
        focusVisible = true
        switch command {
        case .next: move(by: 1)
        case .previous: move(by: -1)
        case .activate: activateSelection()
        }
        return true
    }

    private func move(by delta: Int) {
        selectionID = HyperliteWorkspaceNavigation.movedSelectionID(
            current: selectionID, ids: items.map(\.id), by: delta
        )
    }

    private func activateSelection() {
        guard let selectionID,
              let item = items.first(where: { $0.id == selectionID })
        else { return }
        switch item.action {
        case let .open(url):
            if let url { NSWorkspace.shared.open(url) }
        case .toggleQuietOnes:
            let key = HyperliteHiddenProjectListPresentation.expandedStorageKey
            UserDefaults.standard.set(
                !UserDefaults.standard.bool(forKey: key), forKey: key
            )
        }
    }

    private func editorIsFirstResponder(in window: NSWindow?) -> Bool {
        guard let responder = (window ?? NSApp.keyWindow)?.firstResponder
        else { return false }
        return responder is NSTextView || responder is NSText
    }
}
