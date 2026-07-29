import Foundation

enum HyperliteWorkspaceSizingTests {
    static func run() {
        expect(
            HyperliteWorkspaceSizing.activityViewportHeight(
                availableHeight: 600,
                contentHeight: 240
            ) == 240,
            "short activity should keep its intrinsic height"
        )
        expect(
            HyperliteWorkspaceSizing.activityViewportHeight(
                availableHeight: 600,
                contentHeight: 700
            ) == 502,
            "dense activity should preserve the minimum notepad viewport"
        )
        expect(
            HyperliteWorkspaceSizing.activityViewportHeight(
                availableHeight: 70,
                contentHeight: 700
            ) == 0,
            "activity should not force an undersized workspace to overflow"
        )
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
