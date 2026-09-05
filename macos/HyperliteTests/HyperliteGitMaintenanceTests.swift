import Foundation

enum HyperliteGitMaintenanceTests {
    static func run() {
        testSummary()
        testDecode()
    }

    private static func testSummary() {
        expect(HyperliteGitMaintenance.summary([]) == "No configured repositories to update.",
               "empty results should explain that nothing was configured")
        expect(
            HyperliteGitMaintenance.summary([
                update("kit", "skipped", "already up to date"),
                update("flx", "skipped", "dirty working tree"),
            ]) == "Default branches already up to date (2 skipped).",
            "all-skipped results should not claim an update"
        )
        let mixed = HyperliteGitMaintenance.summary([
            update("kit", "updated", "fast-forwarded main"),
            update("flx", "skipped", "dirty working tree"),
            update("r2", "failed", "fetch: could not resolve host"),
        ])
        expect(mixed?.contains("Updated 1") == true, "summary should count updates")
        expect(mixed?.contains("skipped 1") == true, "summary should count skips")
        expect(mixed?.contains("failed 1") == true, "summary should count failures")
        expect(mixed?.contains("r2: fetch: could not resolve host") == true,
               "summary should include a failure detail")
    }

    private static func testDecode() {
        do {
            let list = try JSONDecoder().decode(
                HyperliteConfiguredProjectList.self,
                from: Data("""
                {"projects":[{"id":"project:/repo/kit","name":"kit","path":"/repo/kit","repository":"owner/kit","base":"main"}]}
                """.utf8)
            )
            expect(list.projects.count == 1 && list.projects[0].name == "kit",
                   "configured project list JSON should decode")
            expect(list.projects[0].location.lanes.isEmpty,
                   "project list should not invent worktree lanes")
            let updates = try JSONDecoder().decode(
                HyperliteDefaultBranchUpdateList.self,
                from: Data("""
                {"results":[{"name":"kit","path":"/repo/kit","base":"main","outcome":"updated","detail":"fast-forwarded main"}]}
                """.utf8)
            )
            expect(updates.results[0].outcome == "updated",
                   "default-branch update JSON should decode")
        } catch {
            FileHandle.standardError.write(Data("FAIL: decode: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func update(_ name: String, _ outcome: String, _ detail: String)
        -> HyperliteDefaultBranchUpdate
    {
        HyperliteDefaultBranchUpdate(
            name: name, path: "/repo/\(name)", base: "main",
            outcome: outcome, detail: detail
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
