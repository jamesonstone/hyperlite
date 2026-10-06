import Foundation

/// One operational fact about the open pull requests, shown in the header.
struct HyperliteQuickFact: Equatable, Identifiable {
    enum Tone: Equatable { case neutral, attention, alert }
    let id: String
    let text: String
    let help: String
    var tone: Tone = .neutral
}

/// Facts in priority order; the header shows as many as fit.
enum HyperliteQuickFacts {
    static func facts(model: HyperlitePullRequestPanelModel, now: Date) -> [HyperliteQuickFact] {
        let rows = model.sections.flatMap(\.rows)
        let day: TimeInterval = 86_400
        let open = rows.count
        let ready = rows.filter { !$0.isDraft }.count
        let failing = rows.filter { !$0.failedPipelines.isEmpty }.count
        let feedback = rows.filter { ($0.unresolvedReviewThreads ?? 0) > 0 }.count
        let conflicts = rows.filter(\.hasMergeConflict).count
        let olderThan10 = rows.filter { now.timeIntervalSince($0.updatedAt) > 10 * day }.count
        let olderThan30 = rows.filter { now.timeIntervalSince($0.updatedAt) > 30 * day }.count
        let fresh = rows.filter { now.timeIntervalSince($0.updatedAt) < day }.count
        let bots = rows.filter { $0.headRefName.hasPrefix("dependabot/") || $0.headRefName.hasPrefix("renovate/") }.count
        let projectsWithPRs = model.sections.filter { !$0.rows.isEmpty }.count
        let ignored = model.sections.filter(\.project.isIgnored).count
        let running = model.sections.filter { $0.project.workflows?.hasActiveRun == true }.count
        let oldest = rows.map(\.updatedAt).min()

        var facts: [HyperliteQuickFact] = [
            .init(id: "open", text: "\(open) open", help: "Open pull requests across watched projects"),
            .init(id: "projects", text: "\(projectsWithPRs) projects",
                  help: "Projects with open pull requests (\(model.visibleSections.count) shown, \(model.hiddenCount) hidden)"),
        ]
        func add(_ id: String, _ count: Int, _ text: String, _ help: String, _ tone: HyperliteQuickFact.Tone) {
            if count > 0 { facts.append(.init(id: id, text: text, help: help, tone: tone)) }
        }
        let undeployedPRs = HyperliteUndeployedPresentation.pullRequestCount(model.undeployed)
        add("undeployed", model.undeployed.count, undeployedPRs > 0 ? "\(undeployedPRs) not deployed" : "\(model.undeployed.count) deploys failed",
            "Merged pull requests whose deploy did not run (\(model.undeployed.count) project\(model.undeployed.count == 1 ? "" : "s"))", .attention)
        add("failing", failing, "\(failing) failing CI", "Pull requests whose head has a failed check", .alert)
        add("feedback", feedback, "\(feedback) need feedback", "Pull requests with unresolved review threads", .alert)
        add("conflicts", conflicts, "\(conflicts) conflicts", "Pull requests with merge conflicts", .attention)
        add("stale10", olderThan10, "\(olderThan10) >10d", "Pull requests not updated in over 10 days", .attention)
        add("stale30", olderThan30, "\(olderThan30) >30d", "Pull requests not updated in over 30 days", .attention)
        add("ready", ready, "\(ready) ready", "Ready for review (not draft)", .neutral)
        add("drafts", open - ready, "\(open - ready) drafts", "Draft pull requests", .neutral)
        add("fresh", fresh, "\(fresh) updated today", "Updated in the last 24 hours", .neutral)
        add("bots", bots, "\(bots) bot", "Dependabot or Renovate pull requests", .neutral)
        add("running", running, "\(running) running", "Projects with a GitHub Actions run in progress", .neutral)
        add("hidden-alerts", model.hiddenAttentionCount, "\(model.hiddenAttentionCount) hidden failing",
            "Hidden projects (no open pull requests) with a failing pipeline; hover the eye to list them", .alert)
        add("ignored", ignored, "\(ignored) ignored", "Ignored projects (never fetched)", .neutral)
        if let oldest {
            let days = Int(now.timeIntervalSince(oldest) / day)
            if days > 0 { facts.append(.init(id: "oldest", text: "oldest \(days)d", help: "Least recently updated open pull request")) }
        }
        return facts
    }
}
