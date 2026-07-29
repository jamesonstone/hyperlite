import Foundation

enum HyperlitePullRequestRefreshMode: Equatable {
    case local
    case stale
    case force
}

enum HyperlitePullRequestRefresh {
    @MainActor
    static func run(
        mode: HyperlitePullRequestRefreshMode,
        continueIfStale: Bool,
        waitForEvidence: () async throws -> Void,
        onScan: (HyperliteProjectPullRequestScan) -> Void
    ) async throws {
        if mode != .local {
            try await waitForEvidence()
        }
        var decoded = try await scan(mode: mode)
        onScan(decoded)
        if mode == .local, continueIfStale,
           HyperlitePullRequestPresentation.isStale(scan: decoded)
        {
            try await waitForEvidence()
            decoded = try await scan(mode: .stale)
            onScan(decoded)
        }
    }

    private static func scan(
        mode: HyperlitePullRequestRefreshMode
    ) async throws -> HyperliteProjectPullRequestScan {
        var arguments = ["pull-requests", "--json"]
        switch mode {
        case .local:
            arguments.append("--local")
        case .stale:
            break
        case .force:
            arguments.append("--force")
        }
        let data = try await HyperliteProcess.run(
            arguments: arguments,
            operation: "pull request refresh"
        )
        return try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: data)
    }
}
