import Foundation

struct HyperliteWorkScan: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let summary: HyperliteWorkSummary
    let items: [HyperliteWorkItem]
    let errors: [HyperliteDiagnostic]
    let warnings: [HyperliteDiagnostic]

    enum CodingKeys: String, CodingKey {
        case summary, items, errors, warnings
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
    }
}

struct HyperliteWorkSummary: Codable, Equatable {
    let projects: Int
    let activeProjects: Int
    let workItems: Int
    let idleProjects: Int
    let unknownProjects: Int

    enum CodingKeys: String, CodingKey {
        case projects, workItems = "work_items", idleProjects = "idle_projects", unknownProjects = "unknown_projects"
        case activeProjects = "active_projects"
    }
}

struct HyperliteWorkItem: Codable, Equatable, Identifiable {
    let repository: String
    let github: String
    let repositoryPath: String
    let branch: String
    let base: String
    let state: String
    let publication: String
    let nextAction: String
    let updatedAt: Date?
    let worktree: HyperliteWorktree?
    let pullRequest: HyperlitePullRequest?

    var id: String { "\(github):\(branch):\(repositoryPath)" }

    enum CodingKeys: String, CodingKey {
        case repository, github, branch, base, state, publication
        case repositoryPath = "repository_path"
        case nextAction = "next_action"
        case updatedAt = "updated_at"
        case worktree
        case pullRequest = "pull_request"
    }

    var title: String {
        if let pullRequest { return "PR #\(pullRequest.number) · \(branch)" }
        return branch.isEmpty ? base : branch
    }

    var statuses: [HyperliteStatus] {
        var result: [HyperliteStatus] = []
        if pullRequest != nil { result.append(.pullRequest) }
        if let worktree {
            let changed = worktree.staged + worktree.unstaged + worktree.untracked + worktree.conflicted > 0
            if branch == base && changed {
                result.append(.unstaged)
            } else if branch != base || changed || worktree.ahead > 0 || worktree.aheadBase > 0 {
                result.append(.worktree)
            }
        }
        return result
    }

    var needsAttention: Bool { !statuses.isEmpty }

    var clickPath: String {
        worktree?.path ?? repositoryPath
    }
}

struct HyperliteWorktree: Codable, Equatable {
    let path: String
    let staged: Int
    let unstaged: Int
    let untracked: Int
    let conflicted: Int
    let ahead: Int
    let aheadBase: Int

    enum CodingKeys: String, CodingKey {
        case path, staged, unstaged, untracked, conflicted, ahead
        case aheadBase = "ahead_base"
    }
}

enum HyperliteStatus: String, CaseIterable, Equatable {
    case pullRequest
    case worktree
    case unstaged

    var label: String {
        switch self {
        case .pullRequest: "Pull Request"
        case .worktree: "Worktree"
        case .unstaged: "Unstaged Main"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequest: "arrow.up.right.square.fill"
        case .worktree: "square.stack.3d.up.fill"
        case .unstaged: "exclamationmark.triangle.fill"
        }
    }
}

struct HyperlitePullRequest: Codable, Equatable {
    let number: Int
    let title: String
    let url: String
    let draft: Bool
    let ci: String
    let review: String
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

enum HyperlitePresentation {
    static let supportedAgeWindows = [3, 5, 7, 10, 30]

    static func items(scan: HyperliteWorkScan, maxAgeDays: Int, now: Date = Date()) -> [HyperliteWorkItem] {
        let ageDays = min(30, max(3, maxAgeDays))
        let cutoff = now.addingTimeInterval(-Double(ageDays) * 86_400)
        return scan.items.filter { item in
            guard let updatedAt = item.updatedAt else { return false }
            return updatedAt >= cutoff && updatedAt <= now && item.needsAttention
        }.sorted {
            if $0.needsAttention != $1.needsAttention { return $0.needsAttention && !$1.needsAttention }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    static func ageLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "age unknown" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}
