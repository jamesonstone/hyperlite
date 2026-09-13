import Foundation

enum HyperlitePipelineAlertTests {
    static let now = Date(timeIntervalSince1970: 1_789_250_000)

    static func run() {
        testLegacyActivityOmitsAlerts()
        testDecodedAlertsStayUntilPresentation()
        testHideIdleKeepsAlertedProjects()
        testAlertLanternIsOrange()
    }

    private static func testLegacyActivityOmitsAlerts() {
        expect(
            HyperlitePipelineAlertPresentation.alerts(from: nil).isEmpty,
            "missing activity has no pipeline badges"
        )
        var activity = HyperliteProjectWorkflowActivity()
        expect(
            !HyperlitePipelineAlertPresentation.hasAlert(activity),
            "empty activity has no pipeline badges"
        )
        activity.pipelineAlerts = [
            HyperlitePipelineAlert(
                kind: "main", name: "main", conclusion: "FAILURE",
                url: "https://example.com/main", observedAt: now
            ),
            HyperlitePipelineAlert(
                kind: "deploy", name: "prod", conclusion: "ERROR",
                url: "https://example.com/log", observedAt: now
            ),
        ]
        expect(
            HyperlitePipelineAlertPresentation.alerts(from: activity).map(\.title) == ["deploy", "main"],
            "badges sort deploy then main for a stable heading"
        )
        expect(
            HyperlitePipelineAlertPresentation.accessibilityLabel(activity.pipelineAlerts![0])
                == "main pipeline failed",
            "VoiceOver names the failed pipeline"
        )
    }

    private static func testDecodedAlertsStayUntilPresentation() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"catalog":[],"runs":[],"deployments":[],
         "pipeline_alerts":[{"kind":"main","name":"ci","conclusion":"FAILURE",
           "url":"https://github.com/o/r/actions/runs/1","observed_at":"2026-09-13T20:00:00Z"}]}
        """
        guard let activity = try? decoder.decode(HyperliteProjectWorkflowActivity.self, from: Data(json.utf8)) else {
            FileHandle.standardError.write(Data("FAIL: pipeline alerts should decode\n".utf8))
            exit(1)
        }
        expect(
            HyperlitePipelineAlertPresentation.hasAlert(activity) &&
                activity.pipelineAlerts?.first?.title == "main",
            "decoded cache alerts become heading badges"
        )
    }

    private static func testHideIdleKeepsAlertedProjects() {
        var project = HyperliteProjectPullRequests(
            id: "/repo/one", name: "one", path: "/repo/one", repository: "owner/one",
            status: .current, message: nil, checkedAt: now, observedAt: now, pullRequests: []
        )
        project.workflows = HyperliteProjectWorkflowActivity(
            pipelineAlerts: [
                HyperlitePipelineAlert(
                    kind: "deploy", name: "deploy", conclusion: "FAILURE", observedAt: now
                )
            ]
        )
        let section = HyperliteProjectSection(
            id: project.id, repository: "owner/one", project: project, rows: []
        )
        expect(
            HyperliteOpenPRProjectFilter.hasNotableActivity(section, now: now),
            "a failed deploy keeps the project visible under hide-idle"
        )
        expect(
            HyperliteProjectSectionChrome.headingWeight(
                idle: true, chips: [], alerts: project.workflows?.pipelineAlerts ?? []
            ) == .notable,
            "pipeline alerts keep an idle heading notable"
        )
    }

    private static func testAlertLanternIsOrange() {
        expect(
            HyperliteOpenPRProjectStageKind.alert.lanternIsLive &&
                HyperliteOpenPRProjectStageKind.alert.lanternUsesAttentionColor,
            "failed pipelines light an orange lantern"
        )
        expect(
            HyperliteOpenPRProjectStageKind.forSection(
                HyperliteProjectSection(
                    id: "/r", repository: "o/r",
                    project: HyperliteProjectPullRequests(
                        id: "/r", name: "r", path: "/r", repository: "o/r",
                        status: .current, message: nil, checkedAt: now, observedAt: now,
                        pullRequests: []
                    ),
                    rows: []
                ),
                chips: [],
                alerts: [
                    HyperlitePipelineAlert(
                        kind: "main", name: "main", conclusion: "FAILURE", observedAt: now
                    )
                ]
            ) == .alert,
            "idle projects with pipeline alerts use the alert stage"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
