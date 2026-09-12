import Foundation

enum HyperliteActivityPollScheduleTests {
    static let now = Date(timeIntervalSince1970: 1_789_250_000)

    static func run() {
        let allowed = policy(allowed: true, reason: "ok", next: now.addingTimeInterval(60), active: 1)
        expect(step(policy: allowed) == .poll(after: 60), "allowed policy polls after the advertised interval")
        expect(step(policy: policy(allowed: true, reason: "ok", next: now.addingTimeInterval(90), active: 1))
            == .poll(after: 90), "a later eligibility time stretches the delay")
        expect(step(policy: allowed, refreshing: true) == .stop(.refreshing), "a full refresh supersedes polling")
        expect(step(policy: nil) == .stop(.noPolicy), "no policy means no poll")
        expect(step(policy: policy(allowed: true, reason: "ok", next: nil, active: 0)) == .stop(.noActiveRuns),
               "nothing running means no poll")
        expect(step(policy: allowed, visible: false) == .stop(.windowHidden), "hidden window stops polling")
        expect(step(policy: allowed, burstStartedAt: now.addingTimeInterval(-1800)) == .stop(.burstCap),
               "thirty minutes of polling stops the burst")
        expect(step(policy: allowed, burstStartedAt: now.addingTimeInterval(-1799)) == .poll(after: 60),
               "just under the burst cap still polls")
        expect(step(policy: policy(allowed: false, reason: "interval", next: now.addingTimeInterval(20), active: 1))
            == .poll(after: 20), "an interval denial waits until the governor's next eligible time")
        expect(step(policy: policy(allowed: false, reason: "quota_floor", next: now.addingTimeInterval(20), active: 1))
            == .stop(.governorDenied("quota_floor")), "quota denials stop the loop")
        expect(step(policy: policy(allowed: false, reason: "interval", next: nil, active: 1))
            == .stop(.governorDenied("interval")), "an interval denial without a time stops")
        expect(step(policy: policy(allowed: false, reason: "interval", next: now.addingTimeInterval(-5), active: 1))
            == .poll(after: HyperliteActivityPollSchedule.minimumDelay), "a past eligibility time polls almost immediately")
    }

    private static func step(
        policy: HyperliteActivityPollDecision?,
        visible: Bool = true,
        refreshing: Bool = false,
        burstStartedAt: Date? = nil
    ) -> HyperliteActivityPollStep {
        HyperliteActivityPollSchedule.nextStep(HyperliteActivityPollContext(
            policy: policy, isWindowVisible: visible,
            isRefreshingPullRequests: refreshing, burstStartedAt: burstStartedAt, now: now
        ))
    }

    private static func policy(allowed: Bool, reason: String, next: Date?, active: Int) -> HyperliteActivityPollDecision {
        HyperliteActivityPollDecision(
            allowed: allowed, reason: reason, nextEligibleAt: next, activeRunCount: active,
            intervalSeconds: 60, maxBurstSeconds: 1800, pollsThisWindow: 0
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
