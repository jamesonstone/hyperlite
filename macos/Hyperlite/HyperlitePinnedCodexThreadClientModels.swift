import Foundation

struct HyperlitePinnedCodexGlobalState: Decodable {
    let pinnedThreadIDs: [String]

    enum CodingKeys: String, CodingKey {
        case pinnedThreadIDs = "pinned-thread-ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.pinnedThreadIDs) else {
            throw HyperlitePinnedCodexMembershipError.pinListMissing
        }
        do {
            pinnedThreadIDs = try container.decode([String].self, forKey: .pinnedThreadIDs)
        } catch {
            throw HyperlitePinnedCodexMembershipError.pinListMalformed
        }
    }
}

struct HyperlitePinnedCodexThreadMetadata {
    let name: String?
    let title: String?
    let cwd: String?
    let updatedAt: Date?

    var hasUsableTitle: Bool { name != nil || title != nil }
}

enum HyperlitePinnedCodexMembershipError: Error {
    case globalStateTooLarge
    case globalStateMalformed
    case pinListMissing
    case pinListMalformed

    var message: String {
        switch self {
        case .globalStateTooLarge: "Codex pinned-thread state exceeds the safety limit"
        case .globalStateMalformed: "Codex pinned-thread state is malformed"
        case .pinListMissing: "Codex pinned-thread membership is unavailable"
        case .pinListMalformed: "Codex pinned-thread list is malformed"
        }
    }
}
