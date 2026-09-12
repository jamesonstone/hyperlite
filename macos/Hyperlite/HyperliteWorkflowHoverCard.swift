import AppKit
import SwiftUI

struct HyperliteWorkflowHoverLink: Equatable, Identifiable {
    let label: String
    let url: URL

    var id: String { url.absoluteString }
}

struct HyperliteWorkflowHoverSnapshot: Equatable {
    let title: String
    let statusLine: String
    let triggerLine: String
    let deploymentLine: String
    let links: [HyperliteWorkflowHoverLink]

    var accessibilityLabel: String {
        [title, statusLine, triggerLine, deploymentLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum HyperliteWorkflowHoverPresentation {
    static func snapshot(
        chip: HyperliteWorkflowChip,
        now: Date,
        timeZone: TimeZone = .current
    ) -> HyperliteWorkflowHoverSnapshot {
        var links: [HyperliteWorkflowHoverLink] = []
        if let run = chip.run, let raw = run.url, let url = URL(string: raw) {
            links.append(HyperliteWorkflowHoverLink(label: "Open run", url: url))
        }
        if let deployment = chip.deployment, let raw = deployment.logURL, let url = URL(string: raw) {
            links.append(HyperliteWorkflowHoverLink(label: "Open deployment log", url: url))
        }
        return HyperliteWorkflowHoverSnapshot(
            title: chip.title,
            statusLine: statusLine(chip: chip, now: now, timeZone: timeZone),
            triggerLine: triggerLine(run: chip.run),
            deploymentLine: deploymentLine(chip.deployment),
            links: links
        )
    }

    static func statusLine(chip: HyperliteWorkflowChip, now: Date, timeZone: TimeZone) -> String {
        switch chip.state {
        case .idle: "no run observed"
        case .running(let since):
            "running · \(HyperliteWorkflowStripPresentation.elapsedLabel(since: since, now: now))"
        case .staleRunning(let lastSeen):
            "running when \(HyperliteWorkflowStripPresentation.lastSeenLabel(lastSeen, timeZone: timeZone))"
        case .success: "succeeded"
        case .failure: "failed · \(chip.run?.conclusion?.lowercased() ?? "failure")"
        case .cancelled: "cancelled"
        case .neutral: "finished · \(chip.run?.conclusion?.lowercased() ?? "neutral")"
        }
    }

    static func triggerLine(run: HyperliteWorkflowRun?) -> String {
        guard let run else { return "" }
        var parts: [String] = []
        if let event = run.event, !event.isEmpty { parts.append(event) }
        if run.isPullRequestScope, let number = run.pullRequestNumber {
            parts.append("#\(number)" + (run.headRefName.map { " \($0)" } ?? ""))
        } else if let branch = run.headRefName, !branch.isEmpty {
            parts.append("on \(branch)")
        }
        if let runNumber = run.runNumber { parts.append("run #\(runNumber)") }
        return parts.joined(separator: " · ")
    }

    static func deploymentLine(_ deployment: HyperliteDeployment?) -> String {
        guard let deployment else { return "" }
        let state = deployment.state.lowercased().replacingOccurrences(of: "_", with: " ")
        return "\(deployment.environment) · \(state)"
    }
}

struct HyperliteWorkflowHoverCard: View {
    let chip: HyperliteWorkflowChip

    var body: some View {
        let card = HyperliteWorkflowHoverPresentation.snapshot(chip: chip, now: Date())
        return VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(HyperliteTypography.heading)
                .foregroundStyle(HyperliteTheme.primaryText.color)
            Text(card.statusLine)
                .font(HyperliteTypography.compact)
                .foregroundStyle(chip.needsAttention ? HyperliteTheme.orange.color : HyperliteTheme.secondaryText.color)
            if !card.triggerLine.isEmpty {
                Text(card.triggerLine)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            if !card.deploymentLine.isEmpty {
                Text(card.deploymentLine)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            ForEach(card.links) { link in
                Button(link.label) { NSWorkspace.shared.open(link.url) }
                    .buttonStyle(.plain)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.cyan.color)
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(HyperliteTheme.canvas.color)
        .hyperliteTheme()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.accessibilityLabel)
    }
}
