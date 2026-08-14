import Foundation

protocol HyperlitePinboardClient: Sendable {
    func load() async throws -> HyperlitePinboardSnapshot
    func mutate(_ mutation: HyperlitePinboardMutation) async throws -> HyperlitePinboardSnapshot
}

struct HyperliteProcessPinboardClient: HyperlitePinboardClient {
    func load() async throws -> HyperlitePinboardSnapshot {
        let data = try await HyperliteProcess.run(
            arguments: ["pinboard", "show"],
            operation: "load pinboard"
        )
        return try HyperliteJSON.decoder.decode(HyperlitePinboardSnapshot.self, from: data)
    }

    func mutate(_ mutation: HyperlitePinboardMutation) async throws -> HyperlitePinboardSnapshot {
        let encoder = JSONEncoder()
        let request = try encoder.encode(mutation)
        let data = try await HyperliteProcess.run(
            arguments: ["pinboard", "mutate", "--stdin"],
            operation: "update pinboard",
            standardInput: request
        )
        return try HyperliteJSON.decoder.decode(HyperlitePinboardSnapshot.self, from: data)
    }
}
