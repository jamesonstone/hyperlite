import Foundation

enum HyperliteProjectIndexTests {
    static func run() throws {
        try testSchemaDecoding()
        testPathPresentation()
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
        expect(
            HyperliteProjectIndexPresentation.abbreviatedPath(
                lane.path,
                home: "/Users/operator"
            ) == "~/worktrees/hyperlite/GH-7",
            "home paths should be compact without losing location"
        )
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
