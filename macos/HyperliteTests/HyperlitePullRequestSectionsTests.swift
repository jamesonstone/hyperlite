import Foundation

enum HyperlitePullRequestSectionsTests {
    static let now = Date(timeIntervalSince1970: 1_789_250_000)

    static func run() {
        testEveryProjectGetsASection()
        testDuplicateRepositoriesKeepSeparateSections()
        testGroupOrderPrecedesConfigurationOrder()
        testHideIdleProjectsFilter()
        testIdleAndCompactStripsDropQuietChips()
        testIdleHeadingsUseQuieterWeight()
        testHideIdleHiddenSections()
    }

    private static func testEveryProjectGetsASection() {
        let scan = scan(projects: [
            project(path: "/repo/one", repository: "owner/one", numbers: [3, 4]),
            project(path: "/repo/two", repository: "owner/two", numbers: [], status: .cached, message: "network unavailable"),
            project(path: "/repo/three", repository: nil, numbers: []),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        let sections = HyperlitePullRequestSectionPlan.sections(
            scan: scan, groups: HyperlitePullRequestPinning.grouped(rows)
        )
        expect(sections.map(\.id) == ["/repo/one", "/repo/two", "/repo/three"],
               "every configured project gets a section; got \(sections.map(\.id))")
        expect(sections[0].rows.map(\.number) == [3, 4], "rows stay under their project")
        expect(sections[0].pullsURL?.absoluteString == "https://github.com/owner/one/pulls" &&
            sections[0].actionsURL?.absoluteString == "https://github.com/owner/one/actions",
            "GitHub links derive from the repository")
        expect(sections[0].pullsButtonLabel == "Open pull requests for owner/one on GitHub" &&
            sections[0].actionsButtonLabel == "Open GitHub Actions for owner/one",
            "button labels name the repository")
        expect(sections[1].rows.isEmpty && sections[1].idleText == "cached · network unavailable",
               "cached project renders its availability inside its section")
        expect(sections[2].repository == "three" && sections[2].pullsURL == nil && sections[2].actionsURL == nil,
               "a project without a GitHub identity keeps its name and disables links")
        expect(sections[2].idleText == "no open pull requests", "idle current project text")
    }

    private static func testDuplicateRepositoriesKeepSeparateSections() {
        let scan = scan(projects: [
            project(path: "/repo/a", repository: "owner/same", numbers: [1]),
            project(path: "/repo/b", repository: "owner/same", numbers: [2]),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        let sections = HyperlitePullRequestSectionPlan.sections(
            scan: scan, groups: HyperlitePullRequestPinning.grouped(rows)
        )
        expect(sections.count == 2 && sections.map(\.id) == ["/repo/a", "/repo/b"],
               "two configured projects on one repository each keep a section; got \(sections.map(\.id))")
        expect(sections[0].rows.map(\.number) == [1] && sections[1].rows.map(\.number) == [2],
               "each project keeps its own rows")
        expect(sections[0].repository == "owner/same" && sections[1].repository == "owner/same",
               "both sections still display and link the shared repository")
    }

    private static func testGroupOrderPrecedesConfigurationOrder() {
        let scan = scan(projects: [
            project(path: "/repo/one", repository: "owner/one", numbers: [1]),
            project(path: "/repo/two", repository: "owner/two", numbers: [2]),
            project(path: "/repo/three", repository: "owner/three", numbers: []),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        var groups = HyperlitePullRequestPinning.grouped(rows)
        groups.reverse()
        let sections = HyperlitePullRequestSectionPlan.sections(scan: scan, groups: groups)
        expect(sections.map(\.repository) == ["owner/two", "owner/one", "owner/three"],
               "pin-store group order wins, idle projects follow in configuration order; got \(sections.map(\.repository))")
    }

    private static func testHideIdleProjectsFilter() {
        let deploying = HyperliteProjectWorkflowActivity(
            catalog: [],
            runs: [],
            deployments: [HyperliteDeployment(
                environment: "prod", state: "IN_PROGRESS",
                createdAt: now.addingTimeInterval(-30), updatedAt: now
            )],
            observedAt: now
        )
        let scan = scan(projects: [
            project(path: "/repo/one", repository: "owner/one", numbers: [3]),
            project(path: "/repo/two", repository: "owner/two", numbers: []),
            project(path: "/repo/three", repository: "owner/three", numbers: [], workflows: deploying),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        let sections = HyperlitePullRequestSectionPlan.sections(
            scan: scan, groups: HyperlitePullRequestPinning.grouped(rows)
        )
        let shown = HyperliteOpenPRProjectFilter.visibleSections(sections, hideIdle: true, now: now)
        expect(shown.map(\.id) == ["/repo/one", "/repo/three"],
               "hiding idle projects keeps open PRs and active deploys, drops the rest; got \(shown.map(\.id))")
        expect(HyperliteOpenPRProjectFilter.visibleSections(sections, hideIdle: false, now: now).count == 3,
               "showing all keeps every configured project")
    }

    private static func testHideIdleHiddenSections() {
        let scan = scan(projects: [
            project(path: "/repo/one", repository: "owner/one", numbers: [3]),
            project(path: "/repo/two", repository: "owner/two", numbers: []),
            project(path: "/repo/three", repository: "owner/quiet", numbers: []),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        let sections = HyperlitePullRequestSectionPlan.sections(
            scan: scan, groups: HyperlitePullRequestPinning.grouped(rows)
        )
        let hidden = HyperliteOpenPRProjectFilter.hiddenSections(
            sections, hideIdle: true, now: now
        )
        expect(hidden.map(\.id) == ["/repo/two", "/repo/three"],
               "hidden idle sections are the complement of the visible list; got \(hidden.map(\.id))")
        expect(
            HyperliteOpenPRProjectFilter.hiddenSections(sections, hideIdle: false, now: now).isEmpty,
            "showing all projects leaves the collapsible idle list empty"
        )
    }

    private static func testIdleAndCompactStripsDropQuietChips() {
        let chips = [
            HyperliteWorkflowChip(id: "ci.yaml", title: "ci", state: .idle, run: nil, deployment: nil),
            HyperliteWorkflowChip(
                id: "deploy.yaml", title: "deploy",
                state: .running(since: now.addingTimeInterval(-30)),
                run: nil, deployment: nil
            ),
            HyperliteWorkflowChip(id: "codeql", title: "codeql", state: .failure, run: nil, deployment: nil),
        ]
        expect(
            HyperliteProjectSectionChrome.stripChips(chips, idle: true, compact: false).map(\.id)
                == ["deploy.yaml", "codeql"],
            "idle projects keep only running and attention chips"
        )
        expect(
            HyperliteProjectSectionChrome.stripChips(chips, idle: false, compact: true).map(\.id)
                == ["deploy.yaml", "codeql"],
            "compact rows keep only running and attention chips"
        )
        expect(
            HyperliteProjectSectionChrome.stripChips(chips, idle: false, compact: false).map(\.id)
                == ["ci.yaml", "deploy.yaml", "codeql"],
            "wide active projects still list every workflow"
        )
    }

    private static func testIdleHeadingsUseQuieterWeight() {
        let quiet = [
            HyperliteWorkflowChip(id: "ci.yaml", title: "ci", state: .idle, run: nil, deployment: nil),
        ]
        let deploying = [
            HyperliteWorkflowChip(
                id: "deploy.yaml", title: "deploy",
                state: .running(since: now.addingTimeInterval(-30)),
                run: nil, deployment: nil
            ),
        ]
        expect(
            HyperliteProjectSectionChrome.headingWeight(idle: false, chips: quiet) == .active,
            "projects with open PRs keep heading weight"
        )
        expect(
            HyperliteProjectSectionChrome.headingWeight(idle: true, chips: deploying) == .notable,
            "idle projects with running work stay secondary, not heading"
        )
        expect(
            HyperliteProjectSectionChrome.headingWeight(idle: true, chips: quiet) == .idle,
            "quiet idle projects use compact weight"
        )
    }

    private static func scan(projects: [HyperliteProjectPullRequests]) -> HyperliteProjectPullRequestScan {
        HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: now, checkedAt: now, observedAt: now, rateLimit: nil,
            refreshIntervalSeconds: 300, projects: projects, errors: [], warnings: []
        )
    }

    private static func project(
        path: String,
        repository: String?,
        numbers: [Int],
        status: HyperliteProjectPullRequestStatus = .current,
        message: String? = nil,
        workflows: HyperliteProjectWorkflowActivity? = nil
    ) -> HyperliteProjectPullRequests {
        let name = String(path.split(separator: "/").last ?? "")
        return HyperliteProjectPullRequests(
            id: path, name: name, path: path, repository: repository, status: status, message: message,
            checkedAt: now, observedAt: now,
            pullRequests: numbers.map { number in
                HyperliteProjectPullRequest(
                    id: "\(repository ?? name)#\(number)", number: number, title: "PR \(number)",
                    url: "https://github.com/\(repository ?? name)/pull/\(number)",
                    headRefName: "GH-\(number)", headRefOID: "head-\(number)",
                    isDraft: false, hasMergeConflict: false, unresolvedReviewThreads: 0,
                    updatedAt: now.addingTimeInterval(Double(-number))
                )
            },
            workflows: workflows
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
