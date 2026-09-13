import AppKit
import SwiftUI

enum HyperlitePipelineAlertPresentation {
    static func alerts(from activity: HyperliteProjectWorkflowActivity?) -> [HyperlitePipelineAlert] {
        let alerts = activity?.pipelineAlerts ?? []
        return alerts.sorted { lhs, rhs in
            if lhs.kind == rhs.kind { return lhs.name < rhs.name }
            return lhs.kind < rhs.kind
        }
    }

    static func hasAlert(_ activity: HyperliteProjectWorkflowActivity?) -> Bool {
        !(activity?.pipelineAlerts ?? []).isEmpty
    }

    static func accessibilityLabel(_ alert: HyperlitePipelineAlert) -> String {
        "\(alert.title) pipeline failed"
    }
}

struct HyperlitePipelineAlertStrip: View {
    let alerts: [HyperlitePipelineAlert]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(alerts) { alert in
                HyperlitePipelineAlertBadge(alert: alert)
            }
        }
    }
}

struct HyperlitePipelineAlertBadge: View {
    let alert: HyperlitePipelineAlert

    var body: some View {
        Button {
            open()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(HyperliteTheme.red.color)
                    .frame(width: 6, height: 6)
                Text(alert.title)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.orange.color)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .help(helpText)
        .accessibilityLabel(HyperlitePipelineAlertPresentation.accessibilityLabel(alert))
        .accessibilityHint(url == nil ? "" : "Opens the failed GitHub Actions run")
    }

    private var url: URL? {
        guard let value = alert.url, let parsed = URL(string: value) else { return nil }
        return parsed
    }

    private var helpText: String {
        if alert.kind == "deploy" {
            return "\(alert.name) deploy failed"
        }
        return "\(alert.name) pipeline failed"
    }

    private func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
