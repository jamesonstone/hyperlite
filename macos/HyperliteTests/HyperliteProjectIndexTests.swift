import Foundation

enum HyperliteProjectIndexTests {
    static func run() throws {
        try testSchemaDecoding()
        testPathPresentation()
        testOpenPullRequestLaneProjection()
    }

    private static func testSchemaDecoding() throws {
        let data = Data("""
        {
          "schema_version": 2,
          "generated_at": "2026-07-29T12:00:00Z",
          "remote_refresh_interval_seconds": 300,
          "summary": {
            "projects": 1, "threads": 0, "attention": 0,
            "in_flight": 0, "completed": 0, "errors": 0, "warnings": 0
          },
          "project_index": [{
            "id": "/repo/hyperlite",
            "name": "hyperlite",
            "path": "/repo/hyperlite",
            "repository": "owner/hyperlite",
            "lanes": [
              {
                "id": "/repo/hyperlite",
                "branch": "main",
                "path": "/repo/hyperlite",
                "primary": true,
                "detached": false
              },
              {
                "id": "/worktrees/hyperlite/GH-7",
                "branch": "GH-7",
                "path": "/worktrees/hyperlite/GH-7",
                "primary": false,
                "detached": false
              }
            ]
          }],
          "threads": [],
          "errors": [],
          "warnings": []
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(HyperliteThreadScan.self, from: data)
        let project = try require(scan.projectIndex?.first, "project index should decode")
        expect(project.name == "hyperlite", "project name should decode")
        expect(project.lanes.map(\.branch) == ["main", "GH-7"],
               "configured and worktree lanes should retain order")
    }

    private static func testPathPresentation() {
        let lane = HyperliteProjectLane(
            id: "/Users/operator/worktrees/hyperlite/GH-7",
            branch: "GH-7",
            path: "/Users/operator/worktrees/hyperlite/GH-7",
            primary: false,
            detached: false
        )
        expect(HyperliteProjectIndexPresentation.laneLabel(lane) == "GH-7",
               "branch should identify the lane")
        expect(HyperliteProjectIndexPresentation.laneKind(lane) == "worktree",
               "secondary lanes should identify themselves as worktrees")
        expect(
            HyperliteProjectIndexPresentation.abbreviatedPath(
                lane.path,
                home: "/Users/operator"
            ) == "~/worktrees/hyperlite/GH-7",
            "home paths should be compact without losing location"
        )
    }

    private static func testOpenPullRequestLaneProjection() {
        let primary = HyperliteProjectLane(
            id: "/repo/hyperlite", branch: "main", path: "/repo/hyperlite",
            primary: true, detached: false
        )
        expect(HyperliteProjectIndexPresentation.laneKind(primary) == "branch",
               "primary lanes should identify themselves as branches")
        let open = HyperliteProjectLane(
            id: "/worktrees/hyperlite/GH-9", branch: "GH-9",
            path: "/worktrees/hyperlite/GH-9", primary: false, detached: false
        )
        let merged = HyperliteProjectLane(
            id: "/worktrees/hyperlite/GH-7", branch: "GH-7",
            path: "/worktrees/hyperlite/GH-7", primary: false, detached: false
        )
        let detached = HyperliteProjectLane(
            id: "/worktrees/hyperlite/PR-10", branch: "GH-9",
            path: "/worktrees/hyperlite/PR-10", primary: false, detached: true
        )
        let project = HyperliteProjectLocation(
            id: "/repo/hyperlite", name: "hyperlite", path: "/repo/hyperlite",
            repository: "owner/hyperlite",
            lanes: [primary, merged, detached, open]
        )
        let pullRequest = HyperliteProjectPullRequest(
            id: "owner/hyperlite#10", number: 10, title: "Open",
            url: "https://github.com/owner/hyperlite/pull/10",
            headRefName: "GH-9", isDraft: false,
            unresolvedReviewThreads: 0, updatedAt: Date()
        )
        let scan = HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(),
            observedAt: Date(), refreshIntervalSeconds: 300,
            projects: [HyperliteProjectPullRequests(
                id: project.id, name: project.name, path: project.path,
                repository: project.repository, status: .current, message: nil,
                checkedAt: Date(), observedAt: Date(), pullRequests: [pullRequest]
            )],
            errors: [], warnings: []
        )

        let visible = HyperliteProjectIndexPresentation.visibleProjects(
            [project], pullRequests: scan
        )
        expect(visible[0].lanes.map(\.branch) == ["main", "GH-9"],
               "only an attached exact open-PR branch should remain visible")

        let configuredFallback = HyperliteProjectIndexPresentation.configuredProjects(
            [], pullRequests: scan
        )
        expect(configuredFallback.map(\.id) == [project.id] && configuredFallback[0].lanes.isEmpty,
               "pull-request data should retain configured projects while the local scan loads")

        let cachedScan = HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(),
            observedAt: Date(), refreshIntervalSeconds: 300,
            projects: [HyperliteProjectPullRequests(
                id: project.id, name: project.name, path: project.path,
                repository: project.repository, status: .cached,
                message: "Cached pull request data is older than five minutes",
                checkedAt: Date(), observedAt: Date(), pullRequests: [pullRequest]
            )],
            errors: [], warnings: []
        )
        let cached = HyperliteProjectIndexPresentation.visibleProjects(
            [project], pullRequests: cachedScan
        )
        expect(cached[0].lanes.map(\.branch) == ["main"],
               "cached PR evidence should not present a worktree as active")

        let mergedScan = HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(),
            observedAt: Date(), refreshIntervalSeconds: 300,
            projects: [HyperliteProjectPullRequests(
                id: project.id, name: project.name, path: project.path,
                repository: project.repository, status: .current, message: nil,
                checkedAt: Date(), observedAt: Date(), pullRequests: []
            )],
            errors: [], warnings: []
        )
        let afterMerge = HyperliteProjectIndexPresentation.visibleProjects(
            [project], pullRequests: mergedScan
        )
        expect(afterMerge[0].lanes.map(\.branch) == ["main"],
               "a successful merged-PR refresh should remove its worktree row")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    private struct TestFailure: Error {
        let message: String
    }
}
