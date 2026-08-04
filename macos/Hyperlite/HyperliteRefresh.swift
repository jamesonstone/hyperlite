import Foundation

extension HyperliteState {
    func refreshAll() {
        refresh()
        HyperlitePinnedCodexThreadState.shared.refresh(force: true)
        refreshDailyNoteDateIfNeeded()
    }

    func refreshAllIfStale(now: Date = Date()) {
        refreshIfStale(now: now)
        HyperlitePinnedCodexThreadState.shared.refreshIfSourceChanged()
        refreshDailyNoteDateIfNeeded(now: now)
    }

    func refreshDailyNoteDateIfNeeded(now: Date? = nil) {
        Task {
            await HyperliteNotepadState.shared.refreshDailyDateIfNeeded(now: now)
        }
    }
}
