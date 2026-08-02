import Foundation

extension HyperliteState {
    func refreshAll() {
        refresh()
        HyperlitePinnedCodexThreadState.shared.refresh(force: true)
    }

    func refreshAllIfStale(now: Date = Date()) {
        refreshIfStale(now: now)
        HyperlitePinnedCodexThreadState.shared.refreshIfSourceChanged()
    }
}
