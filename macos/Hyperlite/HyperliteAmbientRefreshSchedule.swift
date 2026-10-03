import Foundation

/// Pure schedule for the ambient Open PRs refresh. While the window is
/// visible, the app asks for a stale refresh every `checkInterval`; the Go
/// helper only re-queries repositories past its five-minute floor, so a
/// frequent check stays cheap and the list never ages much past that floor.
enum HyperliteAmbientRefreshSchedule {
    static let checkInterval: TimeInterval = 60

    static func shouldCheck(isWindowVisible: Bool, isRefreshing: Bool) -> Bool {
        isWindowVisible && !isRefreshing
    }
}
