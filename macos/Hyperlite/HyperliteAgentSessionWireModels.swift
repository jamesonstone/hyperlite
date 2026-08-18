import Foundation

struct HyperliteAgentSession: Decodable, Equatable, Identifiable {
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
    let actions: [HyperliteAgentPendingAction]
    let routing: HyperliteAgentRouting
    let openInClient: Bool
    let synthetic: Bool

    var currentAction: HyperliteAgentPendingAction? { actions.first }
    var pendingActionCount: Int { actions.count }
    var needsAttention: Bool { !actions.isEmpty || phase.needsAttention }
    var displayTitle: String { title.isEmpty ? project : title }

    var actionIdentity: HyperliteAgentActionIdentity? {
        guard let action = currentAction else { return nil }
        return HyperliteAgentActionIdentity(
            sessionID: id,
            requestID: action.requestID,
            revision: action.revision ?? revision
        )
    }

    var routeDestination: HyperliteAgentRouteDestination? {
        HyperliteAgentRoutePolicy.destination(openInClient: openInClient, routing: routing)
    }

    init(
        id: String,
        provider: String,
        profile: String,
        sessionID: String,
        parentID: String?,
        project: String,
        title: String,
        phase: HyperliteAgentSessionPhase,
        source: String,
        revision: UInt64,
        createdAt: Date,
        updatedAt: Date,
        messages: [HyperliteAgentMessage],
        latestResult: String?,
        action: HyperliteAgentPendingAction?,
        actions: [HyperliteAgentPendingAction]? = nil,
        routing: HyperliteAgentRouting,
        openInClient: Bool,
        synthetic: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.profile = profile
        self.sessionID = sessionID
        self.parentID = parentID
        self.project = project
        self.title = title
        self.phase = phase
        self.source = source
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.latestResult = latestResult
        self.actions = actions ?? action.map { [$0] } ?? []
        self.routing = routing
        self.openInClient = openInClient
        self.synthetic = synthetic
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, profile, project, title, phase, source, revision, messages
        case actions, action, routing, synthetic
        case sessionID = "session_id"
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case latestResult = "latest_result"
        case openInClient = "open_in_client"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(String.self, forKey: .provider)
        profile = try values.decode(String.self, forKey: .profile)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        parentID = try values.decodeIfPresent(String.self, forKey: .parentID)
        project = try values.decode(String.self, forKey: .project)
        title = try values.decode(String.self, forKey: .title)
        phase = try values.decode(HyperliteAgentSessionPhase.self, forKey: .phase)
        source = try values.decode(String.self, forKey: .source)
        revision = try values.decode(UInt64.self, forKey: .revision)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        messages = try values.decode([HyperliteAgentMessage].self, forKey: .messages)
        latestResult = try values.decodeIfPresent(String.self, forKey: .latestResult)
        if let queued = try values.decodeIfPresent([HyperliteAgentPendingAction].self, forKey: .actions) {
            actions = Array(queued.prefix(8))
        } else if let legacy = try values.decodeIfPresent(HyperliteAgentPendingAction.self, forKey: .action) {
            actions = [legacy]
        } else {
            actions = []
        }
        routing = try values.decode(HyperliteAgentRouting.self, forKey: .routing)
        openInClient = try values.decode(Bool.self, forKey: .openInClient)
        synthetic = try values.decodeIfPresent(Bool.self, forKey: .synthetic) ?? false
    }
}

struct HyperliteAgentSessionSnapshot: Decodable, Equatable {
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

    func popupTransition(from previous: HyperliteAgentSessionSnapshot?) -> HyperliteAgentPopupTransition? {
        let previousByID = HyperliteAgentSessionSelection.newestByID(previous?.sessions ?? [])
        if sessions.contains(where: { session in
            guard session.needsAttention else { return false }
            guard let old = previousByID[session.id] else { return true }
            return old.actionIdentity != session.actionIdentity || !old.needsAttention
        }) {
            return .attention
        }
        guard previous != nil else { return nil }
        if sessions.contains(where: { session in
            guard session.phase == .completed || session.phase == .error else { return false }
            return previousByID[session.id]?.phase != session.phase
        }) {
            return .completion
        }
        return nil
    }
}

struct HyperliteAgentActionRequest: Codable, Equatable {
    let schema: String
    let provider: String
    let sessionID: String
    let requestID: String
    let revision: UInt64
    let action: String
    let answers: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case schema, provider, revision, action, answers
        case sessionID = "session_id"
        case requestID = "request_id"
    }

    init(
        schema: String = hyperliteAgentActionSchema,
        provider: String,
        sessionID: String,
        requestID: String,
        revision: UInt64,
        action: String,
        answers: [String: [String]]?
    ) {
        self.schema = schema
        self.provider = provider
        self.sessionID = sessionID
        self.requestID = requestID
        self.revision = revision
        self.action = action
        self.answers = answers
    }
}

struct HyperliteAgentControlRequest: Codable, Equatable {
    let schema = hyperliteAgentControlSchema
    let operation: String
    let profile: String?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case schema, operation, profile
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
    case health(HyperliteAgentIntegrationHealth)

    static func decode(_ data: Data) throws -> HyperliteAgentWireRecord {
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let schema = envelope?["schema"] as? String
        switch schema {
        case hyperliteAgentSnapshotSchema, hyperliteAgentSnapshotSchemaV1:
            return .snapshot(try HyperliteJSON.decoder.decode(HyperliteAgentSessionSnapshot.self, from: data))
        case hyperliteAgentActionResultSchema:
            return .actionResult(try HyperliteJSON.decoder.decode(HyperliteAgentActionResult.self, from: data))
        case hyperliteAgentHealthSchema:
            return .health(try HyperliteJSON.decoder.decode(HyperliteAgentIntegrationHealth.self, from: data))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown agent wire schema"))
        }
    }
}
