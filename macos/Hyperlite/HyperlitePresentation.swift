import Foundation

enum HyperliteFeatureFlags {
    static let inferredAttentionPresentation = false
}

enum HyperlitePresentation {
    static func attentionThreads(scan: HyperliteThreadScan) -> [HyperliteThread] {
        activeThreads(scan: scan).filter(\.hasUnseenAttention)
    }

    static func informationalThreads(scan: HyperliteThreadScan) -> [HyperliteThread] {
        activeThreads(scan: scan).filter { !$0.hasUnseenAttention }
    }

    static func activeThreads(scan: HyperliteThreadScan) -> [HyperliteThread] {
        scan.threads.filter(\.active).sorted {
            if $0.hasUnseenAttention != $1.hasUnseenAttention {
                return $0.hasUnseenAttention
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    static func rowSummary(for thread: HyperliteThread) -> String? {
        thread.hasUnseenAttention ? thread.whyNow : nil
    }

    static func ageLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "age unknown" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    static func remoteIsStale(scan: HyperliteThreadScan, now: Date) -> Bool {
        guard let observedAt = scan.remoteObservedAt else { return true }
        let interval = max(1, scan.remoteRefreshIntervalSeconds ?? 300)
        return now.timeIntervalSince(observedAt) >= Double(interval)
    }

    static func coordinationProjection(_ scan: HyperliteThreadScan) -> String {
        scan.threads.map { thread in
            let dependencies = thread.dependencies.map {
                "\($0.kind):\($0.targetThreadID ?? $0.target)"
            }.joined(separator: ",")
            let implications = thread.implications.map(\.summary).joined(separator: ",")
            let obligations = thread.remainingObligations.map(\.summary).joined(separator: ",")
            return [
                thread.id, thread.latestMaterialRevision, thread.phase.rawValue,
                thread.goal, thread.rationale, dependencies, implications, obligations,
                thread.whyNow, thread.inferenceStatus,
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
    }
}
