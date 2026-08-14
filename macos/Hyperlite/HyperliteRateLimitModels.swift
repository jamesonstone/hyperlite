import Foundation

struct HyperliteGitHubRateLimit: Codable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetAt: Date
    let cost: Int
    let nodeCount: Int
    let observedAt: Date
    let burnRate: HyperliteGitHubRateLimitBurnRate?

    enum CodingKeys: String, CodingKey {
        case limit, used, remaining, cost
        case resetAt = "reset_at"
        case nodeCount = "node_count"
        case observedAt = "observed_at"
        case burnRate = "burn_rate"
    }

    init(
        limit: Int,
        used: Int,
        remaining: Int,
        resetAt: Date,
        cost: Int,
        nodeCount: Int,
        observedAt: Date,
        burnRate: HyperliteGitHubRateLimitBurnRate? = nil
    ) {
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetAt = resetAt
        self.cost = cost
        self.nodeCount = nodeCount
        self.observedAt = observedAt
        self.burnRate = burnRate
    }
}

struct HyperliteGitHubRateLimitBurnRate: Codable, Equatable {
    let pointsPerHour: Double
    let sampleSeconds: Int
    let projectedExhaustionAt: Date?

    enum CodingKeys: String, CodingKey {
        case pointsPerHour = "points_per_hour"
        case sampleSeconds = "sample_seconds"
        case projectedExhaustionAt = "projected_exhaustion_at"
    }
}

enum HyperliteRateLimitLevel: Equatable {
    case unknown
    case healthy
    case warning
    case critical
}

enum HyperliteRateLimitBurnLevel: Equatable {
    case measuring
    case sustainable
    case risk
}
