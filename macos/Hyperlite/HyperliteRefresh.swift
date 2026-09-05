import Foundation

extension HyperliteState {
    func refreshAll() {
        refresh()
        refreshDailyNoteDateIfNeeded()
    }

    func refreshAllIfStale(now: Date = Date()) {
        refreshIfStale(now: now)
        refreshDailyNoteDateIfNeeded(now: now)
    }

    func refreshDailyNoteDateIfNeeded(now: Date? = nil) {
        Task {
            await HyperliteNotepadState.shared.refreshDailyDateIfNeeded(now: now)
        }
    }
}
