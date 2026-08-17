import Foundation

let hyperliteAgentSnapshotSchema = "agent_session_snapshot.v1"
let hyperliteAgentActionSchema = "agent_session_action.v1"
let hyperliteAgentActionResultSchema = "agent_session_action_result.v1"

enum HyperliteAgentSessionPhase: String, Codable, Equatable {
    case starting
    case processing
    case waitingForApproval = "waiting_for_approval"
    case waitingForInput = "waiting_for_input"
    case idle
    case completed
    case error
    case ended

    var needsAttention: Bool { self == .waitingForApproval || self == .waitingForInput }
    var isActive: Bool { self == .starting || self == .processing }

    var label: String {
        switch self {
        case .starting: "Starting"
        case .processing: "Processing"
        case .waitingForApproval: "Approval needed"
        case .waitingForInput: "Input needed"
        case .idle: "Idle"
        case .completed: "Completed"
        case .error: "Error"
        case .ended: "Ended"
        }
    }

    var symbol: String {
        switch self {
        case .starting: "hourglass"
        case .processing: "gearshape.2"
        case .waitingForApproval: "exclamationmark.shield"
        case .waitingForInput: "questionmark.bubble"
        case .idle: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        case .ended: "stop.circle"
        }
    }
}

struct HyperliteAgentMessage: Codable, Equatable {
    let role: String
    let text: String
}

struct HyperliteAgentPendingAction: Codable, Equatable {
    let requestID: String
    let kind: String
    let title: String
    let context: String
    let arguments: [String: String]?
    let completeContext: Bool
    let canAllowOnce: Bool
    let canDeny: Bool
    let canAnswer: Bool
    let canAllowSession: Bool
    let canRevoke: Bool

    enum CodingKeys: String, CodingKey {
        case kind, title, context, arguments
        case requestID = "request_id"
        case completeContext = "complete_context"
        case canAllowOnce = "can_allow_once"
        case canDeny = "can_deny"
        case canAnswer = "can_answer"
        case canAllowSession = "can_allow_session"
        case canRevoke = "can_revoke"
    }
}

struct HyperliteAgentRouting: Codable, Equatable {
    let bundleID: String?
    let terminal: String?
    let terminalID: String?
    let tmuxSession: String?
    let tmuxPane: String?
    let workspacePath: String?

    enum CodingKeys: String, CodingKey {
        case terminal
        case bundleID = "bundle_id"
        case terminalID = "terminal_id"
        case tmuxSession = "tmux_session"
        case tmuxPane = "tmux_pane"
        case workspacePath = "workspace_path"
    }
}

struct HyperliteAgentSession: Codable, Equatable, Identifiable {
    let id: String
    let provider: String
    let profile: String
    let sessionID: String
    let parentID: String?
    let project: String
    let title: String
    let phase: HyperliteAgentSessionPhase
    let source: String
    let revision: UInt64
    let createdAt: Date
    let updatedAt: Date
    let messages: [HyperliteAgentMessage]
    let latestResult: String?
    let action: HyperliteAgentPendingAction?
    let routing: HyperliteAgentRouting
    let openInClient: Bool

    enum CodingKeys: String, CodingKey {
        case id, provider, profile, project, title, phase, source, revision, messages, action, routing
        case sessionID = "session_id"
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case latestResult = "latest_result"
        case openInClient = "open_in_client"
    }

    var needsAttention: Bool { action != nil || phase.needsAttention }
    var displayTitle: String { title.isEmpty ? project : title }
}

struct HyperliteAgentIntegration: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let detected: Bool
    let enabled: Bool
    let actionMode: String
    let target: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case id, name, provider, detected, enabled, target, message
        case actionMode = "action_mode"
    }
}

struct HyperliteAgentSessionSnapshot: Codable, Equatable {
    let schema: String
    let generation: UInt64
    let generatedAt: Date
    let sessions: [HyperliteAgentSession]
    let integrations: [HyperliteAgentIntegration]

    enum CodingKeys: String, CodingKey {
        case schema, generation, sessions, integrations
        case generatedAt = "generated_at"
    }

    var attentionCount: Int { sessions.filter(\.needsAttention).count }
    var activeCount: Int { sessions.filter { $0.phase.isActive }.count }
}

struct HyperliteAgentActionRequest: Codable, Equatable {
    let schema = hyperliteAgentActionSchema
    let sessionID: String
    let requestID: String
    let revision: UInt64
    let action: String
    let answers: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case schema, revision, action, answers
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

struct HyperliteAgentActionResult: Codable, Equatable {
    let schema: String
    let sessionID: String
    let requestID: String
    let action: String
    let status: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case schema, action, status, message
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

enum HyperliteAgentWireRecord: Equatable {
    case snapshot(HyperliteAgentSessionSnapshot)
    case actionResult(HyperliteAgentActionResult)

    static func decode(_ data: Data) throws -> HyperliteAgentWireRecord {
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let schema = envelope?["schema"] as? String
        switch schema {
        case hyperliteAgentSnapshotSchema:
            return .snapshot(try HyperliteJSON.decoder.decode(HyperliteAgentSessionSnapshot.self, from: data))
        case hyperliteAgentActionResultSchema:
            return .actionResult(try HyperliteJSON.decoder.decode(HyperliteAgentActionResult.self, from: data))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown agent wire schema"))
        }
    }
}
