import Foundation

struct HyperliteRateLimitPresentation: Equatable {
    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private let integerFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            formatter.maximumFractionDigits = 0
            return formatter
        }()
        private let decimalFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
            return formatter
        }()
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
            return formatter
        }()

        func format(_ value: Int) -> String? {
            withLock { integerFormatter.string(from: NSNumber(value: value)) }
        }

        func format(_ value: Double) -> String? {
            withLock { decimalFormatter.string(from: NSNumber(value: value)) }
        }

        func timestamp(_ date: Date, timeZone: TimeZone) -> String {
            withLock {
                dateFormatter.timeZone = timeZone
                return dateFormatter.string(from: date)
            }
        }

        private func withLock<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }

    private static let formatterCache = FormatterCache()

    let usedText: String
    let limitText: String
    let usedDetailText: String
    let limitDetailText: String
    let remainingDetailText: String
    let resetText: String
    let costText: String
    let nodeCountText: String
    let observedText: String
    let burnRateText: String
    let burnSampleText: String
    let projectedExhaustionText: String
    let burnComparisonText: String
    let statusText: String
    let usageFraction: Double?
    let accessibilityLabel: String
    let level: HyperliteRateLimitLevel
    let burnLevel: HyperliteRateLimitBurnLevel

    static func make(
        rateLimit: HyperliteGitHubRateLimit?,
        timeZone: TimeZone = .current
    ) -> HyperliteRateLimitPresentation {
        guard let rateLimit, isComplete(rateLimit) else {
            return HyperliteRateLimitPresentation(
                usedText: "?",
                limitText: "?",
                usedDetailText: "—",
                limitDetailText: "—",
                remainingDetailText: "—",
                resetText: "—",
                costText: "—",
                nodeCountText: "—",
                observedText: "—",
                burnRateText: "Measuring",
                burnSampleText: "Needs two observations",
                projectedExhaustionText: "—",
                burnComparisonText: "Awaiting trend",
                statusText: "Unavailable",
                usageFraction: nil,
                accessibilityLabel: "GitHub GraphQL rate limit unavailable",
                level: .unknown,
                burnLevel: .measuring
            )
        }
        let level = level(remaining: rateLimit.remaining, limit: rateLimit.limit)
        let reset = timestamp(rateLimit.resetAt, timeZone: timeZone)
        let observed = timestamp(rateLimit.observedAt, timeZone: timeZone)
        let used = formatted(rateLimit.used)
        let limit = formatted(rateLimit.limit)
        let remaining = formatted(rateLimit.remaining)
        let cost = formatted(rateLimit.cost)
        let nodes = formatted(rateLimit.nodeCount)
        let status = levelDescription(level)
        let burn = burnRatePresentation(rateLimit: rateLimit, timeZone: timeZone)
        return HyperliteRateLimitPresentation(
            usedText: String(rateLimit.used),
            limitText: String(rateLimit.limit),
            usedDetailText: used,
            limitDetailText: limit,
            remainingDetailText: remaining,
            resetText: reset,
            costText: cost,
            nodeCountText: nodes,
            observedText: observed,
            burnRateText: burn.rateText,
            burnSampleText: burn.sampleText,
            projectedExhaustionText: burn.projectedExhaustionText,
            burnComparisonText: burn.comparisonText,
            statusText: status,
            usageFraction: Double(rateLimit.used) / Double(rateLimit.limit),
            accessibilityLabel: "GitHub GraphQL rate limit, \(status.lowercased()), " +
                "\(used) of \(limit) calls used, \(remaining) remaining, resets " +
                "\(reset), last query cost \(cost), node count \(nodes), " +
                "observed \(observed), \(burn.accessibilityText)",
            level: level,
            burnLevel: burn.level
        )
    }

    private struct BurnRatePresentation {
        let rateText: String
        let sampleText: String
        let projectedExhaustionText: String
        let comparisonText: String
        let accessibilityText: String
        let level: HyperliteRateLimitBurnLevel
    }

    private static func burnRatePresentation(
        rateLimit: HyperliteGitHubRateLimit,
        timeZone: TimeZone
    ) -> BurnRatePresentation {
        guard let burnRate = rateLimit.burnRate,
              burnRate.pointsPerHour.isFinite,
              burnRate.pointsPerHour >= 0,
              burnRate.sampleSeconds >= 60
        else {
            return measuringBurnRate()
        }
        let sample = sampleDuration(burnRate.sampleSeconds)
        if burnRate.pointsPerHour == 0,
           burnRate.projectedExhaustionAt == nil {
            return BurnRatePresentation(
                rateText: "0 pts/hr",
                sampleText: sample,
                projectedExhaustionText: "No depletion projected",
                comparisonText: "Through reset",
                accessibilityText: "burn rate zero quota points per hour over " +
                    "\(sample), no depletion projected before reset",
                level: .sustainable
            )
        }
        guard burnRate.pointsPerHour > 0,
              let projectedAt = burnRate.projectedExhaustionAt,
              projectedAt >= rateLimit.observedAt,
              projectedExhaustionIsConsistent(
                  projectedAt,
                  observedAt: rateLimit.observedAt,
                  remaining: rateLimit.remaining,
                  pointsPerHour: burnRate.pointsPerHour
              )
        else {
            return measuringBurnRate()
        }
        let projected = timestamp(projectedAt, timeZone: timeZone)
        let beforeReset = projectedAt < rateLimit.resetAt
        let comparison = beforeReset ? "Before reset" : "After reset"
        let rate = "\(formatted(burnRate.pointsPerHour)) pts/hr"
        return BurnRatePresentation(
            rateText: rate,
            sampleText: sample,
            projectedExhaustionText: projected,
            comparisonText: comparison,
            accessibilityText: "burn rate \(rate) over \(sample), projected " +
                "exhaustion \(projected), \(comparison.lowercased())",
            level: beforeReset ? .risk : .sustainable
        )
    }

    private static func measuringBurnRate() -> BurnRatePresentation {
        BurnRatePresentation(
            rateText: "Measuring",
            sampleText: "Needs two observations",
            projectedExhaustionText: "—",
            comparisonText: "Awaiting trend",
            accessibilityText: "burn rate measuring, needs two valid observations",
            level: .measuring
        )
    }

    private static func projectedExhaustionIsConsistent(
        _ projectedAt: Date,
        observedAt: Date,
        remaining: Int,
        pointsPerHour: Double
    ) -> Bool {
        let expectedSeconds = Double(remaining) / pointsPerHour * 3600
        return expectedSeconds.isFinite &&
            abs(projectedAt.timeIntervalSince(observedAt) - expectedSeconds) <= 1
    }

    private static func isComplete(_ rateLimit: HyperliteGitHubRateLimit) -> Bool {
        rateLimit.limit > 0 && rateLimit.used >= 0 &&
            rateLimit.remaining >= 0 && rateLimit.used <= rateLimit.limit &&
            rateLimit.remaining <= rateLimit.limit &&
            rateLimit.used == rateLimit.limit - rateLimit.remaining &&
            rateLimit.cost >= 0 && rateLimit.nodeCount >= 0
    }

    private static func level(remaining: Int, limit: Int) -> HyperliteRateLimitLevel {
        let percentage = Double(remaining) / Double(limit)
        if percentage <= 0.10 { return .critical }
        if percentage <= 0.20 { return .warning }
        return .healthy
    }

    private static func levelDescription(_ level: HyperliteRateLimitLevel) -> String {
        switch level {
        case .unknown: return "Unavailable"
        case .healthy: return "Healthy capacity"
        case .warning: return "Low capacity warning"
        case .critical: return "Critical capacity"
        }
    }

    private static func formatted(_ value: Int) -> String {
        formatterCache.format(value) ?? String(value)
    }

    private static func formatted(_ value: Double) -> String {
        formatterCache.format(value) ?? String(value)
    }

    private static func sampleDuration(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return "\(hours) hr sample"
        }
        let minutes = Double(seconds) / 60
        return "\(formatted(minutes)) min sample"
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        formatterCache.timestamp(date, timeZone: timeZone)
    }
}
