import Foundation

/// Opens an interactive `git wt sweep` in Terminal with the helper PATH.
enum HyperliteWorktreeSweep {
    static func start() throws {
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
