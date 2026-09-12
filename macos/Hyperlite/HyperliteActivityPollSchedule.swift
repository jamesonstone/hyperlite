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
        if let burstStartedAt = context.burstStartedAt,
           context.now.timeIntervalSince(burstStartedAt) >= maxBurst
        {
            return .stop(.burstCap)
        }
        let advertised = TimeInterval(max(policy.intervalSeconds, 0))
        let interval = advertised > 0 ? advertised : Self.interval
        if policy.allowed {
            let untilEligible = policy.nextEligibleAt.map { $0.timeIntervalSince(context.now) } ?? 0
            return .poll(after: max(interval, untilEligible, minimumDelay))
        }
        guard policy.reason == HyperliteActivityPollDecision.intervalReason,
              let nextEligibleAt = policy.nextEligibleAt
        else {
            return .stop(.governorDenied(policy.reason))
        }
        let wait = nextEligibleAt.timeIntervalSince(context.now)
        guard wait <= maxBurst else { return .stop(.governorDenied(policy.reason)) }
        return .poll(after: max(wait, minimumDelay))
    }
}
