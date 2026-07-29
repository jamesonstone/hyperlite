import AppKit
import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan

    private var rows: [HyperlitePullRequestRow] {
        HyperlitePullRequestPresentation.rows(scan: scan)
    }

    private var availability: [HyperliteProjectPullRequests] {
        HyperlitePullRequestPresentation.availability(scan: scan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Open PRs")
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(.secondary)
                Text("\(rows.count)")
                    .font(HyperliteTypography.bold(10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(freshnessLabel)
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(.tertiary)
            }

            if rows.isEmpty && availability.isEmpty {
                Text("No open pull requests")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(rows) { row in
                            HyperlitePullRequestPanelRow(row: row)
                        }
                        ForEach(availability) { project in
                            HyperlitePullRequestAvailabilityRow(project: project)
                        }
                    }
                }
                .frame(height: scrollHeight)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open pull requests across configured projects")
    }

    private var freshnessLabel: String {
        guard let observedAt = scan.observedAt else { return "GitHub availability limited" }
        let age = HyperlitePresentation.ageLabel(for: observedAt)
        return age == "now" ? "Updated now" : "Updated \(age) ago"
    }

    private var scrollHeight: CGFloat {
        let visibleRows = rows.count + availability.count
        return min(176, max(20, CGFloat(visibleRows * 19)))
    }
}

private struct HyperlitePullRequestPanelRow: View {
    let row: HyperlitePullRequestRow

    var body: some View {
        Button(action: openPullRequest) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(row.projectName)
                    .frame(width: 78, alignment: .leading)
                    .foregroundStyle(.tertiary)
                Text("#\(row.number)")
                    .frame(width: 42, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(row.isDraft ? "draft" : "ready")
                    .frame(width: 42, alignment: .leading)
                    .foregroundStyle(row.isDraft ? .tertiary : .secondary)
                Text(row.title)
                    .foregroundStyle(row.status == .current ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(HyperlitePresentation.ageLabel(for: row.updatedAt))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(HyperliteTypography.regular(10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.url == nil)
        .help(row.url?.absoluteString ?? "Pull request URL is unavailable")
        .accessibilityLabel(
            "\(row.projectName) pull request \(row.number), " +
                "\(row.isDraft ? "draft" : "ready"), \(row.title)"
        )
    }

    private func openPullRequest() {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct HyperlitePullRequestAvailabilityRow: View {
    let project: HyperliteProjectPullRequests

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(project.name)
                .frame(width: 78, alignment: .leading)
            Text(project.status == .cached ? "cached" : "unavailable")
                .frame(width: 91, alignment: .leading)
            Text(project.message ?? "GitHub data is unavailable")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(HyperliteTypography.regular(10))
        .foregroundStyle(.tertiary)
        .help(project.message ?? "GitHub data is unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(project.name), \(project.status.rawValue), " +
                "\(project.message ?? "GitHub data is unavailable")"
        )
    }
}
