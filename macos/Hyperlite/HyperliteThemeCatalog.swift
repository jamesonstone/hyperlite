import SwiftUI

struct HyperliteThemeDescriptor: Equatable, Identifiable {
    let id: String
    let family: String
    let variant: String
    let palette: HyperliteColorPalette

    var title: String { "\(family) \(variant)" }
    var isLight: Bool { palette.colorScheme == .light }
}

enum HyperliteThemeCatalog {
    static let defaultID = "selenized-dark"

    static let all: [HyperliteThemeDescriptor] = [
        descriptor("selenized-dark", "Selenized", "Dark", HyperliteThemePalettes.selenizedDark),
        descriptor("selenized-light", "Selenized", "Light", HyperliteThemePalettes.selenizedLight),
        descriptor("github-dark", "GitHub", "Dark", HyperliteThemePalettes.githubDark),
        descriptor("github-light", "GitHub", "Light", HyperliteThemePalettes.githubLight),
        descriptor("gruvbox-dark", "Gruvbox", "Dark", HyperliteThemePalettes.gruvboxDark),
        descriptor("gruvbox-light", "Gruvbox", "Light", HyperliteThemePalettes.gruvboxLight),
        descriptor("monokai-dark", "Monokai", "Dark", HyperliteThemePalettes.monokaiDark),
        descriptor("monokai-light", "Monokai", "Light", HyperliteThemePalettes.monokaiLight),
        descriptor("tokyo-night", "Tokyo Night", "Dark", HyperliteThemePalettes.tokyoNight),
        descriptor("tokyo-night-day", "Tokyo Night", "Light", HyperliteThemePalettes.tokyoNightDay),
        descriptor("one-dark", "One", "Dark", HyperliteThemePalettes.oneDark),
        descriptor("one-light", "One", "Light", HyperliteThemePalettes.oneLight),
        descriptor("dracula-dark", "Dracula", "Dark", HyperliteThemePalettes.draculaDark),
        descriptor("dracula-light", "Dracula", "Light", HyperliteThemePalettes.draculaLight),
        descriptor("catppuccin-mocha", "Catppuccin", "Dark", HyperliteThemePalettes.catppuccinMocha),
        descriptor("catppuccin-latte", "Catppuccin", "Light", HyperliteThemePalettes.catppuccinLatte),
        descriptor("nord-dark", "Nord", "Dark", HyperliteThemePalettes.nordDark),
        descriptor("nord-light", "Nord", "Light", HyperliteThemePalettes.nordLight),
        descriptor("pink-dark", "Pink Accent", "Dark", HyperliteThemePalettes.pinkDark),
        descriptor("pink-light", "Pink Accent", "Light", HyperliteThemePalettes.pinkLight),
        descriptor("lilac-dark", "Lilac Accent", "Dark", HyperliteThemePalettes.lilacDark),
        descriptor("lilac-light", "Lilac Accent", "Light", HyperliteThemePalettes.lilacLight),
    ]

    static func palette(for id: String) -> HyperliteColorPalette {
        all.first { $0.id == normalizedID(id) }?.palette ?? all[0].palette
    }

    static func descriptor(for id: String) -> HyperliteThemeDescriptor {
        all.first { $0.id == normalizedID(id) } ?? all[0]
    }

    static func normalizedID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.contains { $0.id == trimmed } ? trimmed : defaultID
    }

    private static func descriptor(
        _ id: String,
        _ family: String,
        _ variant: String,
        _ palette: HyperliteColorPalette
    ) -> HyperliteThemeDescriptor {
        HyperliteThemeDescriptor(id: id, family: family, variant: variant, palette: palette)
    }
}
