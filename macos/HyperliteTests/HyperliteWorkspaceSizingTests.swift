import Foundation

enum HyperliteWorkspaceSizingTests {
    static func run() {
        let availableHeight: CGFloat = 628
        let sectionHeight = HyperliteWorkspaceSizing.sectionHeight(
            availableHeight: availableHeight
        )
        expect(
            approximatelyEqual(sectionHeight, 200),
            "each section should receive one third after fixed spacing"
        )
        expect(
            approximatelyEqual(
                sectionHeight * HyperliteWorkspaceSizing.sectionCount +
                    HyperliteWorkspaceSizing.sectionSpacing * 2,
                availableHeight
            ),
            "three sections and two gaps should exactly fill the workspace"
        )
        expect(
            HyperliteWorkspaceSizing.sectionHeight(availableHeight: 20) == 0,
            "an undersized workspace should not produce negative section heights"
        )
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
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
