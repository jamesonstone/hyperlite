import AppKit

enum HyperliteTypographyTests {
    static func run() {
        expect(
            HyperliteTypography.family == "JetBrainsMono Nerd Font",
            "the application font contract should use the exact Nerd Font family"
        )
        expect(
            HyperliteTypography.resolveFamily(
                in: ["Menlo", "jetbrainsmono nerd font"]
            ) == "jetbrainsmono nerd font",
            "font resolution should preserve the installed family spelling"
        )
        expect(
            HyperliteTypography.resolveFamily(in: ["Menlo"]) == nil,
            "a missing application family should select the fallback"
        )

        let fallback = HyperliteTypography.appKitFont(
            13,
            weight: .medium,
            family: nil
        )
        let expected = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        expect(
            fallback.fontName == expected.fontName,
            "the shared SwiftUI/AppKit resolver should use the monospaced fallback"
        )
        let plainText = HyperliteTypography.plainTextAppKitFont(13)
        let expectedPlainText = HyperliteTypography.appKitFont(13)
        expect(
            plainText.fontName == expectedPlainText.fontName,
            "notepad content should use the application font contract"
        )

        if let installed = HyperliteTypography.resolveFamily(
            in: NSFontManager.shared.availableFontFamilies
        ) {
            expect(
                plainText.familyName == installed,
                "notepad content should resolve the installed Nerd Font family"
            )
            let resolved = HyperliteTypography.appKitFont(
                13,
                weight: .semibold,
                family: installed
            )
            expect(
                resolved.familyName == installed,
                "native editing should resolve the installed Nerd Font family"
            )
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
