import Foundation

extension HyperliteState {
    /// Keeps Open PRs current without operator action. The loop lives for the
    /// app's lifetime; each tick is a cheap no-op unless the window is visible
    /// and the cached scan is stale.
    func startAmbientRefresh() {
        ambientRefreshTask?.cancel()
        ambientRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HyperliteAmbientRefreshSchedule.checkInterval))
                guard let self, !Task.isCancelled else { return }
                if HyperliteAmbientRefreshSchedule.shouldCheck(
                    isWindowVisible: activityPolling.isWindowVisible,
                    isRefreshing: isRefreshingPullRequests
                ) {
                    refreshIfStale()
                }
            }
        }
    }
}
