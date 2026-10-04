import AppKit
import SwiftUI

enum HyperliteTypography {
    static let family = "JetBrainsMono Nerd Font"

    private static let resolvedFamily = resolveFamily(
        in: NSFontManager.shared.availableFontFamilies
    )

    static var body: Font { regular(HyperliteAppearance.shared.bodySize) }
    static var compact: Font { regular(HyperliteAppearance.shared.compactSize) }
    static var heading: Font { semibold(HyperliteAppearance.shared.bodySize) }
    static var sectionHeading: Font { semibold(HyperliteAppearance.shared.bodySize + 2) }
    static var title: Font { semibold(HyperliteAppearance.shared.bodySize + 5) }
    static var chrome: Font { regular(HyperliteAppearance.shared.bodySize + 1) }

    static func regular(_ size: CGFloat) -> Font {
        swiftUIFont(size: size, weight: .regular)
    }

    static func medium(_ size: CGFloat) -> Font {
        swiftUIFont(size: size, weight: .medium)
    }

    static func semibold(_ size: CGFloat) -> Font {
        swiftUIFont(size: size, weight: .semibold)
    }

    static func bold(_ size: CGFloat) -> Font {
        swiftUIFont(size: size, weight: .bold)
    }

    static func appKitFont(
        _ size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        appKitFont(size, weight: weight, family: resolvedFamily)
    }

    static func resolveFamily(in installedFamilies: [String]) -> String? {
        installedFamilies.first {
            $0.compare(
                family,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    static func appKitFont(
        _ size: CGFloat,
        weight: NSFont.Weight,
        family: String?
    ) -> NSFont {
        if let family {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [NSFontDescriptor.TraitKey.weight: weight],
            ])
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Fonts are matched once per size and weight. Every row reads several
    /// fonts on each render, and font descriptor matching is expensive.
    private static func swiftUIFont(size: CGFloat, weight: NSFont.Weight) -> Font {
        fontCache.font(size: size, weight: weight) { Font(appKitFont(size, weight: weight)) }
    }

    private static let fontCache = HyperliteFontCache()
}

private final class HyperliteFontCache: @unchecked Sendable {
    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
    }

    private let lock = NSLock()
    private var fonts: [Key: Font] = [:]

    func font(size: CGFloat, weight: NSFont.Weight, make: () -> Font) -> Font {
        let key = Key(size: size, weight: weight.rawValue)
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[key] { return font }
        let font = make()
        fonts[key] = font
        return font
    }
}
