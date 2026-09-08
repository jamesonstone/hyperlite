import Combine
import Foundation
import SwiftUI

enum HyperliteWindowChrome {
    static let title = "👻 hyperlite"
}

enum HyperliteWorkspaceArrangement: Equatable {
    case stacked
    case verticalSplit

    static func current(verticalMode: Bool) -> Self {
        verticalMode ? .verticalSplit : .stacked
    }
}

enum HyperliteFontSize: Int, CaseIterable, Identifiable {
    case readable = 12
    case compact = 10

    var id: Int { rawValue }
    var title: String { "\(rawValue) pt" }
    var subtitle: String {
        switch self {
        case .readable: "Default list size; compact chrome stays 10 pt"
        case .compact: "Compact list size; compact chrome stays 8 pt"
        }
    }

    var compactChrome: CGFloat { self == .readable ? 10 : 8 }
}

final class HyperliteAppearance: ObservableObject {
    static let shared = HyperliteAppearance()

    @Published private(set) var themeID: String
    @Published private(set) var fontSize: HyperliteFontSize
    @Published private(set) var verticalMode: Bool
    @Published private(set) var notesOnly: Bool
    @Published private(set) var stackedSplitFraction: Double
    @Published private(set) var verticalSplitFraction: Double

    private let defaults: UserDefaults

    var palette: HyperliteColorPalette {
        HyperliteThemeCatalog.palette(for: themeID)
    }

    var bodySize: CGFloat { CGFloat(fontSize.rawValue) }
    var compactSize: CGFloat { fontSize.compactChrome }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTheme = defaults.string(forKey: Keys.themeID) ?? ""
        themeID = HyperliteThemeCatalog.normalizedID(storedTheme)
        let storedSize = defaults.integer(forKey: Keys.fontSize)
        fontSize = HyperliteFontSize(rawValue: storedSize) ?? .readable
        verticalMode = defaults.bool(forKey: Keys.verticalMode)
        notesOnly = defaults.bool(forKey: Keys.notesOnly)
        stackedSplitFraction = defaults.object(forKey: Keys.stackedSplitFraction) as? Double
            ?? HyperliteWorkspaceSplit.fitContent
        if let storedVertical = defaults.object(forKey: Keys.verticalSplitFraction) as? Double {
            verticalSplitFraction = HyperliteWorkspaceSplit.clamped(storedVertical)
        } else {
            verticalSplitFraction = HyperliteWorkspaceSplit.defaultVerticalFraction
        }
    }

    func setTheme(_ id: String) {
        let normalized = HyperliteThemeCatalog.normalizedID(id)
        guard normalized != themeID else { return }
        themeID = normalized
        defaults.set(normalized, forKey: Keys.themeID)
    }

    func setFontSize(_ size: HyperliteFontSize) {
        guard size != fontSize else { return }
        fontSize = size
        defaults.set(size.rawValue, forKey: Keys.fontSize)
    }

    func setVerticalMode(_ enabled: Bool) {
        guard enabled != verticalMode else { return }
        verticalMode = enabled
        defaults.set(enabled, forKey: Keys.verticalMode)
    }

    func toggleVerticalMode() {
        setVerticalMode(!verticalMode)
    }

    func setNotesOnly(_ enabled: Bool) {
        guard enabled != notesOnly else { return }
        notesOnly = enabled
        defaults.set(enabled, forKey: Keys.notesOnly)
    }

    func toggleNotesOnly() {
        setNotesOnly(!notesOnly)
    }

    func setStackedSplitFraction(_ value: Double) {
        let next = value <= HyperliteWorkspaceSplit.fitContent
            ? HyperliteWorkspaceSplit.fitContent
            : HyperliteWorkspaceSplit.clamped(value)
        guard next != stackedSplitFraction else { return }
        stackedSplitFraction = next
        defaults.set(next, forKey: Keys.stackedSplitFraction)
    }

    func setVerticalSplitFraction(_ value: Double) {
        let next = HyperliteWorkspaceSplit.clamped(value)
        guard next != verticalSplitFraction else { return }
        verticalSplitFraction = next
        defaults.set(next, forKey: Keys.verticalSplitFraction)
    }

    func resetStackedSplit() {
        setStackedSplitFraction(HyperliteWorkspaceSplit.fitContent)
    }

    func resetVerticalSplit() {
        setVerticalSplitFraction(HyperliteWorkspaceSplit.defaultVerticalFraction)
    }

    private enum Keys {
        static let themeID = "hyperlite.appearance.theme-id"
        static let fontSize = "hyperlite.appearance.font-size"
        static let verticalMode = "hyperlite.appearance.vertical-mode"
        static let notesOnly = "hyperlite.appearance.notes-only"
        static let stackedSplitFraction = "hyperlite.appearance.stacked-split-fraction"
        static let verticalSplitFraction = "hyperlite.appearance.vertical-split-fraction"
    }
}
