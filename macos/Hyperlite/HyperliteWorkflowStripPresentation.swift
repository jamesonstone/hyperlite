import Foundation

enum HyperliteWorkflowChipState: Equatable {
    case idle
    case running(since: Date)
    case staleRunning(lastSeen: Date)
    case success
    case failure
    case cancelled
    case neutral
}

struct HyperliteWorkflowChip: Equatable, Identifiable {
    let id: String
    let title: String
    let state: HyperliteWorkflowChipState
    let run: HyperliteWorkflowRun?
    let deployment: HyperliteDeployment?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var needsAttention: Bool {
        switch state {
        case .failure, .staleRunning: true
        default: false
        }
    }

    func accessibilityLabel(now: Date, timeZone: TimeZone = .current) -> String {
        switch state {
        case .idle: "\(title) idle"
        case .running(let since):
            "\(title) running for \(HyperliteWorkflowStripPresentation.elapsedLabel(since: since, now: now))"
        case .staleRunning(let lastSeen):
            "\(title) \(HyperliteWorkflowStripPresentation.lastSeenLabel(lastSeen, timeZone: timeZone))"
        case .success: "\(title) succeeded"
        case .failure: "\(title) failed"
        case .cancelled: "\(title) cancelled"
        case .neutral: "\(title) finished"
        }
    }
}

enum HyperliteWorkflowStripPresentation {
    /// Only an observation this recent may animate a running chip.
    static let freshWindow: TimeInterval = 120
    static let deploymentChipPrefix = "deployment:"

    static func isFresh(_ activity: HyperliteProjectWorkflowActivity, now: Date) -> Bool {
        guard let observedAt = activity.observedAt else { return false }
        return now.timeIntervalSince(observedAt) < freshWindow
    }

    static func chips(
        activity: HyperliteProjectWorkflowActivity?,
        now: Date
    ) -> [HyperliteWorkflowChip] {
        guard let activity else { return [] }
        let fresh = isFresh(activity, now: now)
        let lastSeen = activity.observedAt ?? now
        var files = activity.catalog.map { ($0.file, $0.name) }
        let known = Set(files.map(\.0))
        for run in activity.runs where !known.contains(run.file) &&
            !files.contains(where: { $0.0 == run.file })
        {
            files.append((run.file, run.name))
        }
        var chips = files.map { file, name -> HyperliteWorkflowChip in
            let run = latestRun(activity.runs.filter { $0.file == file })
            return HyperliteWorkflowChip(
                id: file, title: name, state: state(for: run, fresh: fresh, lastSeen: lastSeen),
                run: run, deployment: nil
            )
        }
        var attachedToWorkflow = false
        for deployment in latestActiveDeploymentsByEnvironment(activity.deployments) {
            let state: HyperliteWorkflowChipState = fresh
                ? .running(since: deployment.createdAt)
                : .staleRunning(lastSeen: lastSeen)
            // Attach the newest environment to an existing deploy* workflow
            // chip; every other active environment keeps its own chip so no
            // environment or its log link is dropped.
            if !attachedToWorkflow,
               let index = chips.firstIndex(where: {
                   $0.id.lowercased().hasPrefix("deploy") && $0.deployment == nil
               }) {
                let chip = chips[index]
                chips[index] = HyperliteWorkflowChip(
                    id: chip.id, title: chip.title,
                    state: chip.isRunning ? chip.state : state,
                    run: chip.run, deployment: deployment
                )
                attachedToWorkflow = true
            } else {
                chips.append(HyperliteWorkflowChip(
                    id: deploymentChipPrefix + deployment.environment,
                    title: deployment.environment, state: state, run: nil, deployment: deployment
                ))
            }
        }
        return chips
    }

    /// The newest active deployment per environment, so concurrent deployments
    /// to different environments each keep a chip and log link.
    static func latestActiveDeploymentsByEnvironment(
        _ deployments: [HyperliteDeployment]
    ) -> [HyperliteDeployment] {
        var latest: [String: HyperliteDeployment] = [:]
        for deployment in deployments where deployment.isActive {
            if let existing = latest[deployment.environment], existing.createdAt >= deployment.createdAt {
                continue
            }
            latest[deployment.environment] = deployment
        }
        return latest.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.environment < $1.environment
        }
    }

    static func latestRun(_ runs: [HyperliteWorkflowRun]) -> HyperliteWorkflowRun? {
        let active = runs.filter(\.isActive)
        let candidates = active.isEmpty ? runs : active
        return candidates.max { $0.createdAt < $1.createdAt }
    }

    static func state(
        for run: HyperliteWorkflowRun?,
        fresh: Bool,
        lastSeen: Date
    ) -> HyperliteWorkflowChipState {
        guard let run else { return .idle }
        if run.isActive {
            return fresh ? .running(since: run.createdAt) : .staleRunning(lastSeen: lastSeen)
        }
        switch (run.conclusion ?? "").uppercased() {
        case "SUCCESS": return .success
        case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": return .failure
        case "CANCELLED", "SKIPPED", "STALE": return .cancelled
        case "": return .idle
        default: return .neutral
        }
    }

    static func hasFreshActiveRun(scan: HyperliteProjectPullRequestScan, now: Date) -> Bool {
        scan.projects.contains { project in
            guard let activity = project.workflows else { return false }
            return activity.hasActiveRun && isFresh(activity, now: now)
        }
    }

    /// The earliest moment a currently fresh running chip becomes stale, so
    /// the panel can re-render once without a periodic timer.
    static func nextFreshnessExpiry(scan: HyperliteProjectPullRequestScan, now: Date) -> Date? {
        scan.projects.compactMap { project -> Date? in
            guard let activity = project.workflows, activity.hasActiveRun,
                  let observedAt = activity.observedAt
            else { return nil }
            let expiry = observedAt.addingTimeInterval(freshWindow)
            return expiry > now ? expiry : nil
        }.min()
    }

    static func compactChips(_ chips: [HyperliteWorkflowChip]) -> (visible: [HyperliteWorkflowChip], hiddenCount: Int) {
        (chips.filter { $0.isRunning || $0.needsAttention }, 0)
    }

    static func elapsedLabel(since: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(since).rounded(.down)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(String(format: "%02d", seconds % 60))s" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    static func lastSeenLabel(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "last seen \(formatter.string(from: date))"
    }

    static func headerSummary(chips: [HyperliteWorkflowChip], now: Date, timeZone: TimeZone = .current) -> String {
        let notable = chips.filter { $0.state != .idle }
        guard !notable.isEmpty else { return "no workflow runs observed" }
        return "workflows: " + notable
            .map { $0.accessibilityLabel(now: now, timeZone: timeZone) }
            .joined(separator: ", ")
    }
}
