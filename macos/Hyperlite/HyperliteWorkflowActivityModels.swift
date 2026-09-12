import Foundation

struct HyperliteWorkflowDefinition: Codable, Equatable, Identifiable {
    let file: String
    let name: String
    var url: String? = nil

    var id: String { file }
}

struct HyperliteWorkflowRun: Codable, Equatable {
    static let activeStatuses: Set<String> = ["QUEUED", "IN_PROGRESS", "WAITING", "PENDING", "REQUESTED"]

    let file: String
    let name: String
    let scope: String
    var pullRequestNumber: Int? = nil
    var headRefName: String? = nil
    var headOID: String? = nil
    let status: String
    var conclusion: String? = nil
    var event: String? = nil
    var runNumber: Int? = nil
    var displayTitle: String? = nil
    var url: String? = nil
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case file, name, scope, status, conclusion, event, url
        case pullRequestNumber = "pull_request_number"
        case headRefName = "head_ref_name"
        case headOID = "head_oid"
        case runNumber = "run_number"
        case displayTitle = "display_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isActive: Bool { Self.activeStatuses.contains(status.uppercased()) }
    var isPullRequestScope: Bool { scope == "pull_request" }
}

struct HyperliteDeployment: Codable, Equatable {
    static let activeStates: Set<String> = ["PENDING", "QUEUED", "IN_PROGRESS", "WAITING"]

    let environment: String
    let state: String
    var ref: String? = nil
    var commitOID: String? = nil
    var logURL: String? = nil
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case environment, state, ref
        case commitOID = "commit_oid"
        case logURL = "log_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isActive: Bool { Self.activeStates.contains(state.uppercased()) }
}

struct HyperliteProjectWorkflowActivity: Codable, Equatable {
    var catalog: [HyperliteWorkflowDefinition] = []
    var runs: [HyperliteWorkflowRun] = []
    var deployments: [HyperliteDeployment] = []
    var treeOID: String? = nil
    var checkedAt: Date? = nil
    var observedAt: Date? = nil
    var message: String? = nil

    enum CodingKeys: String, CodingKey {
        case catalog, runs, deployments, message
        case treeOID = "tree_oid"
        case checkedAt = "checked_at"
        case observedAt = "observed_at"
    }

    var hasActiveRun: Bool {
        runs.contains(where: \.isActive) || deployments.contains(where: \.isActive)
    }
}

struct HyperliteActivityPollDecision: Codable, Equatable {
    let allowed: Bool
    let reason: String
    var nextEligibleAt: Date? = nil
    let activeRunCount: Int
    let intervalSeconds: Int
    let maxBurstSeconds: Int
    var burstStartedAt: Date? = nil
    var lastCheckedAt: Date? = nil
    let pollsThisWindow: Int

    enum CodingKeys: String, CodingKey {
        case allowed, reason
        case nextEligibleAt = "next_eligible_at"
        case activeRunCount = "active_run_count"
        case intervalSeconds = "interval_seconds"
        case maxBurstSeconds = "max_burst_seconds"
        case burstStartedAt = "burst_started_at"
        case lastCheckedAt = "last_checked_at"
        case pollsThisWindow = "polls_this_window"
    }

    static let intervalReason = "interval"
}
