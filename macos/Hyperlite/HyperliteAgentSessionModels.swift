import Foundation

let hyperliteAgentSnapshotSchemaV1 = "agent_session_snapshot.v1"
let hyperliteAgentSnapshotSchema = "agent_session_snapshot.v2"
let hyperliteAgentActionSchemaV1 = "agent_session_action.v1"
let hyperliteAgentActionSchema = "agent_session_action.v2"
let hyperliteAgentActionResultSchema = "agent_session_action_result.v1"
let hyperliteAgentControlSchema = "agent_session_control.v1"
let hyperliteAgentHealthSchema = "agent_integration_health.v1"

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
    var revision: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case kind, title, context, arguments, revision
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

struct HyperliteAgentIntegrationHealth: Codable, Equatable, Identifiable {
    let schema: String
    let provider: String
    let profile: String
    let transport: String
    let connectionState: String
    let lastEventAt: Date?
    let lastAcknowledgementAt: Date?
    let watchersUsed: Int
    let watchersLimit: Int
    let filteredCount: UInt64
    let rejectedCount: UInt64
    let selfTestResult: String?
    let errorCode: String?

    var id: String { profile }

    enum CodingKeys: String, CodingKey {
        case schema, provider, profile, transport
        case connectionState = "connection_state"
        case lastEventAt = "last_event_at"
        case lastAcknowledgementAt = "last_acknowledgement_at"
        case watchersUsed = "watchers_used"
        case watchersLimit = "watchers_limit"
        case filteredCount = "filtered_count"
        case rejectedCount = "rejected_count"
        case selfTestResult = "self_test_result"
        case errorCode = "error_code"
    }
}

struct HyperliteAgentActionIdentity: Hashable {
    let sessionID: String
    let requestID: String
    let revision: UInt64
}

enum HyperliteAgentRouteDestination: Equatable {
    case application(String)
    case finder

    var label: String {
        switch self {
        case let .application(name): "Open \(name)"
        case .finder: "Reveal in Finder"
        }
    }
}

enum HyperliteAgentPopupTransition: Equatable {
    case attention
    case completion

    var dismissDelay: UInt64 { self == .attention ? 12 : 6 }
}
