import Foundation

enum HyperliteAmbientRefreshScheduleTests {
    static func run() {
        expect(HyperliteAmbientRefreshSchedule.shouldCheck(isWindowVisible: true, isRefreshing: false),
               "a visible idle window checks for stale pull requests")
        expect(!HyperliteAmbientRefreshSchedule.shouldCheck(isWindowVisible: false, isRefreshing: false),
               "a hidden window spends no quota")
        expect(!HyperliteAmbientRefreshSchedule.shouldCheck(isWindowVisible: true, isRefreshing: true),
               "an in-flight refresh is not stacked")
        expect(HyperliteAmbientRefreshSchedule.checkInterval <= 60,
               "the ambient check runs at least once a minute")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
