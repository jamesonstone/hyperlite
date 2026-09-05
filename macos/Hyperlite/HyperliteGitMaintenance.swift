import Foundation

struct HyperliteConfiguredProjectList: Codable, Equatable {
    let projects: [HyperliteConfiguredProject]
}

struct HyperliteConfiguredProject: Codable, Equatable {
    let id: String
    let name: String
    let path: String
    let repository: String?
    let base: String?

    var location: HyperliteProjectLocation {
        HyperliteProjectLocation(
            id: id, name: name, path: path, repository: repository, lanes: []
        )
    }
}

struct HyperliteDefaultBranchUpdateList: Codable, Equatable {
    let results: [HyperliteDefaultBranchUpdate]
}

struct HyperliteDefaultBranchUpdate: Codable, Equatable {
    let name: String
    let path: String
    let base: String
    let outcome: String
    let detail: String
}

enum HyperliteGitMaintenance {
    static func summary(_ results: [HyperliteDefaultBranchUpdate]) -> String? {
        guard !results.isEmpty else { return "No configured repositories to update." }
        let updated = results.filter { $0.outcome == "updated" }.count
        let skipped = results.filter { $0.outcome == "skipped" }.count
        let failed = results.filter { $0.outcome == "failed" }.count
        if failed == 0 && updated == 0 {
            return "Default branches already up to date (\(skipped) skipped)."
        }
        var parts = ["Updated \(updated)"]
        if skipped > 0 { parts.append("skipped \(skipped)") }
        if failed > 0 { parts.append("failed \(failed)") }
        let headline = parts.joined(separator: ", ") + "."
        let failures = results.filter { $0.outcome == "failed" }.prefix(3).map {
            "\($0.name): \($0.detail)"
        }
        if failures.isEmpty { return headline }
        return headline + " " + failures.joined(separator: " ")
    }

    static func startSweep() throws {
        let path = HyperliteProcessEnvironment.inheriting(ProcessInfo.processInfo.environment)["PATH"] ?? ""
        let executable = path.split(separator: ":").map(String.init).map {
            ($0 as NSString).appendingPathComponent("git-wt")
        }.first { FileManager.default.isExecutableFile(atPath: $0) }
        guard executable != nil else {
            throw HyperliteError.commandFailed("sweep worktrees", "git-wt is not on PATH")
        }
        let command = "PATH=\(appleQuote(path)) exec git wt sweep"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \(appleQuote(command))",
        ]
        try process.run()
    }

    private static func appleQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
