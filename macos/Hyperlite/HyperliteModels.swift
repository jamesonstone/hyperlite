import Foundation

enum HyperliteJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = try? fractionalDateFormat.parse(value) { return date }
            if let date = try? standardDateFormat.parse(value) { return date }
            let container = try decoder.singleValueContainer()
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO-8601 date"
            )
        }
        return decoder
    }()

    nonisolated private static let fractionalDateFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true
    )
    nonisolated private static let standardDateFormat = Date.ISO8601FormatStyle()
}

struct HyperliteDiagnostic: Codable, Equatable, Identifiable {
    let repository: String
    let repositoryPath: String?
    let stage: String
    let message: String
    let code: String?
    let worktreePath: String?

    var id: String {
        [repository, stage, code ?? "", worktreePath ?? "", message].joined(separator: "\u{1F}")
    }

    enum CodingKeys: String, CodingKey {
        case repository, stage, message, code
        case repositoryPath = "repository_path"
        case worktreePath = "worktree_path"
    }
}
