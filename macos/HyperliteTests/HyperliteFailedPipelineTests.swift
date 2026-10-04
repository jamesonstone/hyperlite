import Foundation

enum HyperliteFailedPipelineTests {
    static func run() {
        let shortName = HyperliteFailedPipelinePresentation.shortName
        expect(shortName("Docs Impact Check", "docs-impact.yml") == "docs", "filler and later words drop")
        expect(shortName("Go lint", "ci.yml") == "go lint", "a too-short first word keeps one more")
        expect(shortName("CodeQL", "codeql.yml") == "codeql", "single words stay whole")
        expect(shortName("", "update_docs-check.yaml") == "update", "an unnamed workflow uses its file stem")
        expect(shortName("Workflow", "lint.yml") == "lint", "an all-filler name falls back to the file")
        expect(shortName("Supercalifragilistic", "x.yml").count == 12, "long names truncate")

        let head = "abc"
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func run(_ file: String, _ conclusion: String?, status: String = "COMPLETED",
                 number: Int = 7, oid: String = "abc", at offset: TimeInterval = 0) -> HyperliteWorkflowRun {
            HyperliteWorkflowRun(
                file: file, name: file, scope: "pull_request", pullRequestNumber: number,
                headOID: oid, status: status, conclusion: conclusion,
                createdAt: base.addingTimeInterval(offset), updatedAt: base.addingTimeInterval(offset)
            )
        }
        let failures = HyperliteFailedPipelinePresentation.failures(
            runs: [
                run("docs.yml", "FAILURE"),
                run("lint.yml", "FAILURE"), run("lint.yml", "SUCCESS", at: 60),
                run("test.yml", nil, status: "IN_PROGRESS"),
                run("old.yml", "FAILURE", oid: "previous"),
                run("other.yml", "FAILURE", number: 8),
            ],
            pullRequestNumber: 7, headOID: head
        )
        expect(failures.map(\.file) == ["docs.yml"],
               "only the newest failed run per workflow on this head counts; got \(failures.map(\.file))")
        let external = HyperliteFailedPipelinePresentation.failures(
            runs: [], pullRequestNumber: 7, headOID: head, rollup: "FAILURE"
        )
        expect(external.map(\.shortName) == ["checks"], "a failing rollup without Actions runs is still flagged")
        expect(HyperliteFailedPipelinePresentation.failures(
            runs: [], pullRequestNumber: 7, headOID: head, rollup: "SUCCESS"
        ).isEmpty, "a green rollup shows nothing")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
