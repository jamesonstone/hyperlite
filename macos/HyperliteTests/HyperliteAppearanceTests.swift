import Foundation
import SwiftUI

enum HyperliteAppearanceTests {
    static func run() {
        testCatalogHasElevenFamiliesWithLightAndDark()
        testUnknownThemeFallsBackToSelenizedDark()
        testNestedThemeAndFontEntriesMarkCurrent()
        testIsolatedAppearancePersistence()
        testWindowTitle()
    }

    private static func testCatalogHasElevenFamiliesWithLightAndDark() {
        expect(HyperliteThemeCatalog.all.count == 22,
               "eleven families should each expose light and dark palettes")
        let families = Set(HyperliteThemeCatalog.all.map(\.family))
        expect(families.count == 11, "catalog should contain eleven named families")
        expect(HyperliteThemeCatalog.all.filter(\.isLight).count == 11,
               "every family should include a light variant")
        expect(HyperliteThemeCatalog.all.filter { !$0.isLight }.count == 11,
               "every family should include a dark variant")
        expect(
            HyperliteThemeCatalog.palette(for: "github-light").colorScheme == .light,
            "GitHub Light should use the light color scheme"
        )
        expect(
            ["Gruvbox", "Monokai", "Tokyo Night", "Pink Accent", "Lilac Accent"]
                .allSatisfy(families.contains),
            "requested families should be present"
        )
    }

    private static func testUnknownThemeFallsBackToSelenizedDark() {
        expect(
            HyperliteThemeCatalog.normalizedID("not-a-theme") ==
                HyperliteThemeCatalog.defaultID,
            "unknown theme ids should fall back to Selenized Dark"
        )
    }

    private static func testNestedThemeAndFontEntriesMarkCurrent() {
        let themes = HyperliteInteractionModel.themeEntries(currentID: "tokyo-night")
        expect(themes.count == 22, "Theme nested list should include every palette")
        let current = themes.first { $0.id == "theme:tokyo-night" }
        expect(current?.symbol == "checkmark" && current?.subtitle == "Current",
               "the active theme should be marked in Command-K")
        expect(
            themes.contains { $0.kind == .action(.setTheme("gruvbox-dark")) },
            "nested theme actions should apply a specific palette"
        )
        let sizes = HyperliteInteractionModel.fontSizeEntries(current: .readable)
        expect(sizes.count == 2, "Font Size should expose 12 pt and 10 pt")
        expect(
            sizes.first { $0.id == "font-size:12" }?.symbol == "checkmark",
            "the active font size should be marked"
        )
        expect(
            sizes.contains { $0.kind == .action(.setFontSize(.compact)) },
            "10 pt should remain selectable"
        )
    }

    private static func testIsolatedAppearancePersistence() {
        let suite = "hyperlite.tests.appearance.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "appearance tests need an isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let appearance = HyperliteAppearance(defaults: defaults)
        expect(appearance.themeID == HyperliteThemeCatalog.defaultID,
               "new appearance should default to Selenized Dark")
        expect(appearance.fontSize == .readable,
               "new appearance should default to 12 pt")
        appearance.setTheme("gruvbox-light")
        appearance.setFontSize(.compact)
        let restored = HyperliteAppearance(defaults: defaults)
        expect(restored.themeID == "gruvbox-light" && restored.palette.colorScheme == .light,
               "theme choice should persist and flip native color scheme")
        expect(restored.fontSize == .compact && restored.compactSize == 8,
               "compact font size should persist with 8 pt chrome")
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testWindowTitle() {
        expect(
            HyperliteWindowChrome.title == "👻 hyperlite",
            "the window title should use the lowercase ghost brand"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
