import Foundation

struct HyperliteActivityPollRuntime {
    var task: Task<Void, Never>?
    var generation = 0
    var isPolling = false
    var burstStartedAt: Date?
    var isWindowVisible = true
}

/// The bounded follow-up poll. It runs only after a scan reports running
/// work, only while the window is visible, only while the helper's quota
/// governor allows, and never longer than the burst cap.
extension HyperliteState {
    func setWindowVisible(_ visible: Bool) {
        guard activityPolling.isWindowVisible != visible else { return }
        activityPolling.isWindowVisible = visible
        scheduleActivityPollIfNeeded()
    }

    func cancelActivityPoll() {
        activityPolling.task?.cancel()
        activityPolling.task = nil
        activityPolling.generation += 1
        activityPolling.isPolling = false
    }

    func scheduleActivityPollIfNeeded(now: Date = Date()) {
        cancelActivityPoll()
        guard let scan = pullRequestScan else { return }
        if (scan.activityPolicy?.activeRunCount ?? 0) > 0 {
            if activityPolling.burstStartedAt == nil {
                activityPolling.burstStartedAt = now
            }
        } else {
            activityPolling.burstStartedAt = nil
        }
        let context = HyperliteActivityPollContext(
            policy: scan.activityPolicy,
            isWindowVisible: activityPolling.isWindowVisible,
            isRefreshingPullRequests: isRefreshingPullRequests,
            burstStartedAt: activityPolling.burstStartedAt,
            now: now
        )
        guard case .poll(let delay) = HyperliteActivityPollSchedule.nextStep(context) else { return }
        let generation = activityPolling.generation
        activityPolling.task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled,
                  self.activityPolling.generation == generation
            else { return }
            // Task.sleep can resume later than requested, so re-check the cap
            // before spending quota on a poll past the burst deadline.
            if let startedAt = self.activityPolling.burstStartedAt,
               Date().timeIntervalSince(startedAt) >= HyperliteActivityPollSchedule.maxBurst
            {
                self.cancelActivityPoll()
                return
            }
            await self.runActivityPoll(generation: generation)
        }
    }

    private func runActivityPoll(generation: Int) async {
        activityPolling.isPolling = true
        do {
            let scan = try await HyperlitePullRequestRefresh.activity()
            guard activityPolling.generation == generation, !isRefreshingPullRequests else { return }
            activityPolling.isPolling = false
            replacePullRequestScan(scan)
            // Polls never refresh pull-request rows, so once those pass the
            // five-minute floor the ordinary stale refresh runs instead of
            // letting a watched deploy demote every row to cached.
            if HyperlitePullRequestPresentation.isStale(scan: scan) {
                refreshIfStale()
            } else {
                scheduleActivityPollIfNeeded()
            }
        } catch {
            guard activityPolling.generation == generation else { return }
            activityPolling.isPolling = false
            // A transport failure costs no quota; retry on the same schedule
            // inside the burst cap rather than freezing the strip.
            scheduleActivityPollIfNeeded()
        }
    }
}
