import Foundation

struct HyperliteDeployGap: Codable, Equatable {
    let file: String
    let name: String
    let conclusion: String
    var url: String? = nil
    let attemptAt: Date
    var lastSuccessAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case file, name, conclusion, url
        case attemptAt = "attempt_at"
        case lastSuccessAt = "last_success_at"
    }
}

struct HyperliteUndeployedPullRequest: Codable, Equatable {
    let number: Int
    let title: String
    var url: String? = nil
    var headRefName: String? = nil
    var author: String? = nil
    let mergedAt: Date

    enum CodingKeys: String, CodingKey {
        case number, title, url, author
        case headRefName = "head_ref_name"
        case mergedAt = "merged_at"
    }
}

/// Deploy pipelines on the default branch that are behind their merged pull
/// requests, as the helper observed them.
struct HyperliteDeployStatus: Codable, Equatable {
    var pipelines: [HyperliteDeployGap]? = nil
    var pullRequests: [HyperliteUndeployedPullRequest]? = nil
    var message: String? = nil

    enum CodingKeys: String, CodingKey {
        case pipelines, message
        case pullRequests = "pull_requests"
    }

    var isBehind: Bool { !(pipelines ?? []).isEmpty }
}

/// One project in the NOT DEPLOYED band.
struct HyperliteUndeployedProject: Equatable, Identifiable {
    let section: HyperliteProjectSection
    let pipelines: [HyperliteDeployGap]
    let pullRequests: [HyperliteUndeployedPullRequest]

    var id: String { "undeployed:\(section.id)" }
    var latestAttempt: Date { pipelines.map(\.attemptAt).max() ?? .distantPast }
    var runURL: URL? {
        pipelines.lazy.compactMap { $0.url.flatMap(URL.init(string:)) }.first ?? section.actionsURL
    }

    func rowID(_ pullRequest: HyperliteUndeployedPullRequest) -> String { "\(id)#\(pullRequest.number)" }
}

enum HyperliteUndeployedPresentation {
    static let bandID = "undeployed-band"

    /// Behind projects, most recent failed attempt first. Hidden idle
    /// projects are included: a merged-but-undeployed change matters most
    /// exactly when nothing is open. Ignored projects are never fetched.
    static func projects(_ sections: [HyperliteProjectSection]) -> [HyperliteUndeployedProject] {
        sections.compactMap { section -> HyperliteUndeployedProject? in
            guard !section.project.isIgnored, let status = section.project.workflows?.deploys, status.isBehind else {
                return nil
            }
            return HyperliteUndeployedProject(
                section: section, pipelines: status.pipelines ?? [], pullRequests: status.pullRequests ?? []
            )
        }
        .sorted { $0.latestAttempt > $1.latestAttempt }
    }

    static func pullRequestCount(_ projects: [HyperliteUndeployedProject]) -> Int {
        projects.reduce(0) { $0 + $1.pullRequests.count }
    }

    static func summary(_ projects: [HyperliteUndeployedProject]) -> String {
        let prs = pullRequestCount(projects)
        let projectText = "\(projects.count) project\(projects.count == 1 ? "" : "s")"
        return prs == 0 ? projectText : "\(prs) PR\(prs == 1 ? "" : "s") · \(projectText)"
    }

    /// `deploy ✕ 1d` for a failure, `deploy skipped 1d` for an automatic skip.
    static func pipelineLabel(_ gap: HyperliteDeployGap, now: Date) -> String {
        let age = HyperlitePresentation.ageLabel(for: gap.attemptAt, now: now)
        switch gap.conclusion.uppercased() {
        case "SKIPPED": return "\(gap.name) skipped \(age)"
        case "CANCELLED": return "\(gap.name) cancelled \(age)"
        default: return "\(gap.name) ✕ \(age)"
        }
    }

    static func lastDeployLabel(_ gaps: [HyperliteDeployGap], now: Date) -> String? {
        guard let last = gaps.compactMap(\.lastSuccessAt).min() else { return nil }
        return "last deploy \(HyperlitePresentation.ageLabel(for: last, now: now)) ago"
    }

    static func issueLabel(_ pullRequest: HyperliteUndeployedPullRequest) -> String? {
        HyperliteIssueReference.number(branch: pullRequest.headRefName ?? "", title: pullRequest.title).map { "GH-\($0)" }
    }

    /// Heading badge text: the undeployed PR count, or the failing pipeline
    /// count when only direct pushes are waiting.
    static func badgeCount(_ status: HyperliteDeployStatus) -> Int {
        let prs = status.pullRequests?.count ?? 0
        return prs > 0 ? prs : status.pipelines?.count ?? 0
    }

    static func badgeHelp(_ status: HyperliteDeployStatus) -> String {
        let names = (status.pipelines ?? []).map(\.name).joined(separator: ", ")
        let prs = status.pullRequests?.count ?? 0
        let merged = prs == 0 ? "" : " — \(prs) merged PR\(prs == 1 ? "" : "s") not deployed"
        return "Deploy did not run: \(names)\(merged)"
    }
}
