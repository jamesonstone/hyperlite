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

    static func plainTextAppKitFont(_ size: CGFloat) -> NSFont {
        appKitFont(size)
    }

    static func editorAppKitFont() -> NSFont {
        appKitFont(HyperliteAppearance.shared.bodySize + 1)
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

    private static func swiftUIFont(size: CGFloat, weight: NSFont.Weight) -> Font {
        Font(appKitFont(size, weight: weight))
    }
}
