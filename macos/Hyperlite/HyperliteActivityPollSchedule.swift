import Foundation

enum HyperliteActivityPollStopReason: Equatable {
    case refreshing
    case noPolicy
    case noActiveRuns
    case windowHidden
    case burstCap
    case governorDenied(String)
}

enum HyperliteActivityPollStep: Equatable {
    case poll(after: TimeInterval)
    case stop(HyperliteActivityPollStopReason)
}

struct HyperliteActivityPollContext: Equatable {
    var policy: HyperliteActivityPollDecision?
    var isWindowVisible: Bool
    var isRefreshingPullRequests: Bool
    var burstStartedAt: Date?
    var now: Date
}

/// Pure schedule for the bounded follow-up poll. The Go quota governor owns
/// quota policy; this only decides when the native app may ask again. Window
/// visibility, not app activation, is the "someone is looking" signal so a
/// visible Hyperlite beside an editor keeps its running chips current.
enum HyperliteActivityPollSchedule {
    static let interval: TimeInterval = 60
    static let maxBurst: TimeInterval = 30 * 60
    static let minimumDelay: TimeInterval = 1

    static func nextStep(_ context: HyperliteActivityPollContext) -> HyperliteActivityPollStep {
        if context.isRefreshingPullRequests { return .stop(.refreshing) }
        guard let policy = context.policy else { return .stop(.noPolicy) }
        if policy.activeRunCount <= 0 { return .stop(.noActiveRuns) }
        if !context.isWindowVisible { return .stop(.windowHidden) }
        let remaining = remainingBurst(context)
        if let remaining, remaining <= 0 { return .stop(.burstCap) }
        let advertised = TimeInterval(max(policy.intervalSeconds, 0))
        let interval = advertised > 0 ? advertised : Self.interval
        if policy.allowed {
            let untilEligible = policy.nextEligibleAt.map { $0.timeIntervalSince(context.now) } ?? 0
            return withinBurst(max(interval, untilEligible, minimumDelay), remaining: remaining)
        }
        guard policy.reason == HyperliteActivityPollDecision.intervalReason,
              let nextEligibleAt = policy.nextEligibleAt
        else {
            return .stop(.governorDenied(policy.reason))
        }
        let wait = max(nextEligibleAt.timeIntervalSince(context.now), minimumDelay)
        return withinBurst(wait, remaining: remaining)
    }

    /// Remaining burst budget, or nil when no burst is running. A poll is only
    /// scheduled when it lands before the deadline.
    private static func remainingBurst(_ context: HyperliteActivityPollContext) -> TimeInterval? {
        guard let burstStartedAt = context.burstStartedAt else { return nil }
        return maxBurst - context.now.timeIntervalSince(burstStartedAt)
    }

    private static func withinBurst(
        _ delay: TimeInterval,
        remaining: TimeInterval?
    ) -> HyperliteActivityPollStep {
        if let remaining, delay >= remaining { return .stop(.burstCap) }
        return .poll(after: delay)
    }
}
