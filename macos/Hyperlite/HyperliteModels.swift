import Foundation

struct HyperliteThreadScan: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let remoteObservedAt: Date?
    let remoteRefreshIntervalSeconds: Int?
    let summary: HyperliteThreadSummary
    let threads: [HyperliteThread]
    let errors: [HyperliteDiagnostic]
    let warnings: [HyperliteDiagnostic]

    enum CodingKeys: String, CodingKey {
        case summary, threads, errors, warnings
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case remoteObservedAt = "remote_observed_at"
        case remoteRefreshIntervalSeconds = "remote_refresh_interval_seconds"
    }
}

struct HyperliteThreadSummary: Codable, Equatable {
    let projects: Int
    let threads: Int
    let attention: Int
    let inFlight: Int
    let completed: Int
    let errors: Int
    let warnings: Int

    enum CodingKeys: String, CodingKey {
        case projects, threads, attention, completed, errors, warnings
        case inFlight = "in_flight"
    }
}

enum HyperliteThreadPhase: String, Codable, Equatable {
    case shaping
    case planned
    case implementing
    case reviewing
    case operationalizing
    case reflecting
    case complete

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .shaping: "lightbulb"
        case .planned: "list.bullet.clipboard"
        case .implementing: "hammer"
        case .reviewing: "eye"
        case .operationalizing: "shippingbox"
        case .reflecting: "arrow.triangle.2.circlepath"
        case .complete: "checkmark.circle"
        }
    }
}

struct HyperliteThread: Codable, Equatable, Identifiable {
    let id: String
    let aliases: [String]
    let title: String
    let goal: String
    let rationale: String
    let phase: HyperliteThreadPhase
    let active: Bool
    let repositories: [String]
    let artifacts: [HyperliteArtifact]
    let dependencies: [HyperliteRelation]
    let implications: [HyperliteImplication]
    let obligations: [HyperliteObligation]
    let evidence: [HyperliteEvidence]
    let attention: [HyperliteAttentionMoment]
    let latestMaterialRevision: String
    let whyNow: String
    let confidence: Double
    let inferenceStatus: String
    let note: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, aliases, title, goal, rationale, phase, active, repositories, artifacts
        case dependencies, implications, obligations, evidence, attention, confidence, note
        case latestMaterialRevision = "latest_material_revision"
        case whyNow = "why_now"
        case inferenceStatus = "inference_status"
        case updatedAt = "updated_at"
    }

    var hasUnseenAttention: Bool { attention.contains { !$0.seen } }
    var remainingObligations: [HyperliteObligation] { obligations.filter { !$0.satisfied } }
    var projectName: String {
        repositories.first?.split(separator: "/").last.map(String.init) ?? "Unknown project"
    }
    var primaryURL: URL? {
        artifacts.compactMap(\.url).compactMap(URL.init(string:)).first
    }
    var primaryPath: String? {
        artifacts.compactMap(\.path).first
    }
}

struct HyperliteArtifact: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let repository: String
    let title: String
    let state: String
    let url: String?
    let path: String?
    let evidenceID: String
    let updatedAt: Date?
    let freshness: String

    enum CodingKeys: String, CodingKey {
        case id, kind, repository, title, state, url, path, freshness
        case evidenceID = "evidence_id"
        case updatedAt = "updated_at"
    }
}

struct HyperliteRelation: Codable, Equatable, Identifiable {
    let kind: String
    let targetThreadID: String?
    let target: String
    let basis: String
    let confidence: Double
    let evidenceIDs: [String]

    var id: String { "\(kind):\(targetThreadID ?? target)" }

    enum CodingKeys: String, CodingKey {
        case kind, target, basis, confidence
        case targetThreadID = "target_thread_id"
        case evidenceIDs = "evidence_ids"
    }
}

struct HyperliteImplication: Codable, Equatable, Identifiable {
    let summary: String
    let category: String
    let basis: String
    let confidence: Double
    let evidenceIDs: [String]

    var id: String { "\(category):\(summary)" }

    enum CodingKeys: String, CodingKey {
        case summary, category, basis, confidence
        case evidenceIDs = "evidence_ids"
    }
}

struct HyperliteObligation: Codable, Equatable, Identifiable {
    let id: String
    let summary: String
    let satisfied: Bool
    let basis: String
    let confidence: Double
    let evidenceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, summary, satisfied, basis, confidence
        case evidenceIDs = "evidence_ids"
    }
}

struct HyperliteEvidence: Codable, Equatable, Identifiable {
    let id: String
    let source: String
    let repository: String
    let kind: String
    let title: String
    let url: String?
    let path: String?
    let excerpt: String?
    let updatedAt: Date?
    let freshness: String

    enum CodingKeys: String, CodingKey {
        case id, source, repository, kind, title, url, path, excerpt, freshness
        case updatedAt = "updated_at"
    }
}

struct HyperliteAttentionMoment: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let summary: String
    let why: String
    let revision: String
    let evidenceIDs: [String]
    let createdAt: Date
    let seen: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, summary, why, revision, seen
        case evidenceIDs = "evidence_ids"
        case createdAt = "created_at"
    }
}

struct HyperliteDiagnostic: Codable, Equatable, Identifiable {
    let repository: String
    let repositoryPath: String?
    let stage: String
    let message: String
    let code: String?
    let worktreePath: String?

    var id: String {
        [repository, stage, code ?? "", worktreePath ?? "", message].joined(separator: "\u{1F}")
    }

    var isPrunableWorktree: Bool {
        code == "worktree_prunable" && repositoryPath != nil && worktreePath != nil
    }

    enum CodingKeys: String, CodingKey {
        case repository, stage, message, code
        case repositoryPath = "repository_path"
        case worktreePath = "worktree_path"
    }
}

enum HyperliteThreadSection: Int, CaseIterable {
    case attention
    case inFlight

    var title: String {
        switch self {
        case .attention: "Attention"
        case .inFlight: "In Flight"
        }
    }
}

enum HyperlitePresentation {
    static func threads(
        scan: HyperliteThreadScan,
        section: HyperliteThreadSection
    ) -> [HyperliteThread] {
        let active = activeThreads(scan: scan)
        switch section {
        case .attention:
            return active.filter(\.hasUnseenAttention)
        case .inFlight:
            return active.filter { !$0.hasUnseenAttention }
        }
    }

    static func visibleThreads(scan: HyperliteThreadScan) -> [HyperliteThread] {
        HyperliteThreadSection.allCases.flatMap {
            threads(scan: scan, section: $0)
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

    private static func activeThreads(scan: HyperliteThreadScan) -> [HyperliteThread] {
        scan.threads.filter(\.active).sorted {
            if $0.hasUnseenAttention != $1.hasUnseenAttention {
                return $0.hasUnseenAttention
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
}
