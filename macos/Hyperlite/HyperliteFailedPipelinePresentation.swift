import Foundation

/// A failed GitHub Actions workflow on a pull request's head commit.
struct HyperliteFailedPipeline: Equatable, Identifiable {
    let file: String
    let name: String
    let shortName: String
    let url: URL?

    var id: String { file }
}

enum HyperliteFailedPipelinePresentation {
    static let failedConclusions: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"]
    static let maxShortNameLength = 12
    private static let fillerWords: Set<String> = [
        "check", "checks", "workflow", "workflows", "pipeline", "job", "jobs", "the", "and", "for",
    ]

    /// The newest run per workflow file on this exact head, kept only when it
    /// failed, so a later green rerun clears the warning.
    static func failures(
        runs: [HyperliteWorkflowRun],
        pullRequestNumber: Int,
        headOID: String,
        rollup: String = ""
    ) -> [HyperliteFailedPipeline] {
        let head = headOID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return [] }
        var newest: [String: HyperliteWorkflowRun] = [:]
        for run in runs where run.isPullRequestScope &&
            run.pullRequestNumber == pullRequestNumber && run.headOID == head
        {
            if let current = newest[run.file], current.createdAt >= run.createdAt { continue }
            newest[run.file] = run
        }
        let named = newest.values
            .filter { !$0.isActive && failedConclusions.contains(($0.conclusion ?? "").uppercased()) }
            .map {
                HyperliteFailedPipeline(
                    file: $0.file, name: $0.name,
                    shortName: shortName(name: $0.name, file: $0.file),
                    url: $0.url.flatMap(URL.init(string:))
                )
            }
            .sorted { $0.shortName < $1.shortName }
        // A failing rollup with no failed Actions run comes from another
        // check provider; flag it generically rather than hide it.
        if named.isEmpty, ["FAILURE", "ERROR"].contains(rollup.uppercased()) {
            return [HyperliteFailedPipeline(file: "", name: "a non-Actions check", shortName: "checks", url: nil)]
        }
        return named
    }

    /// The shortest recognizable label: the workflow name without filler
    /// words, falling back to the file stem, first word only unless that word
    /// is too short to recognize. "Docs Impact Check" -> "docs".
    static func shortName(name: String, file: String) -> String {
        var words = significantWords(name)
        if words.isEmpty {
            let stem = (file as NSString).deletingPathExtension
            words = significantWords(stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))
        }
        guard let first = words.first else { return "ci" }
        let label = first.count < 3 && words.count > 1 ? "\(first) \(words[1])" : first
        guard label.count > maxShortNameLength else { return label }
        return String(label.prefix(maxShortNameLength - 1)) + "…"
    }

    private static func significantWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !fillerWords.contains($0) }
    }
}
