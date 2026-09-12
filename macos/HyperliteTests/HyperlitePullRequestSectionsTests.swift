import Foundation

enum HyperlitePullRequestSectionsTests {
    static let now = Date(timeIntervalSince1970: 1_789_250_000)

    static func run() {
        testEveryProjectGetsASection()
        testDuplicateRepositoriesCollapse()
        testGroupOrderPrecedesConfigurationOrder()
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

    private static func testDuplicateRepositoriesCollapse() {
        let scan = scan(projects: [
            project(path: "/repo/a", repository: "owner/same", numbers: [1]),
            project(path: "/repo/b", repository: "owner/same", numbers: [2]),
        ])
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        let sections = HyperlitePullRequestSectionPlan.sections(
            scan: scan, groups: HyperlitePullRequestPinning.grouped(rows)
        )
        expect(sections.count == 1 && sections[0].rows.count == 2 && sections[0].id == "/repo/a",
               "two paths for one repository share one section")
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
        message: String? = nil
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
            }
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
