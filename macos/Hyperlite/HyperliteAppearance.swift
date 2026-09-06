import Combine
import Foundation
import SwiftUI

enum HyperliteWindowChrome {
    static let title = "👻 hyperlite"
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

    private enum Keys {
        static let themeID = "hyperlite.appearance.theme-id"
        static let fontSize = "hyperlite.appearance.font-size"
    }
}
