import Foundation

enum HyperlitePinnedCodexThreadAvailability: Equatable {
    case current
    case partial
    case unavailable
}

struct HyperlitePinnedCodexThread: Equatable, Identifiable {
    let id: String
    let name: String?
    let title: String?
    let cwd: String?
    let updatedAt: Date?
    let metadataResolved: Bool

    var displayTitle: String {
        Self.nonempty(name) ?? Self.nonempty(title) ?? id
    }

    var directoryName: String? {
        guard let cwd = Self.nonempty(cwd) else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

struct HyperlitePinnedCodexThreadSnapshot: Equatable {
    let availability: HyperlitePinnedCodexThreadAvailability
    let checkedAt: Date
    let observedAt: Date?
    let threads: [HyperlitePinnedCodexThread]
    let unresolvedMetadataCount: Int
    let message: String?

    var authoritativeCount: Int? {
        availability == .unavailable ? nil : threads.count
    }

    static func current(
        threads: [HyperlitePinnedCodexThread],
        observedAt: Date
    ) -> HyperlitePinnedCodexThreadSnapshot {
        HyperlitePinnedCodexThreadSnapshot(
            availability: .current,
            checkedAt: observedAt,
            observedAt: observedAt,
            threads: threads,
            unresolvedMetadataCount: 0,
            message: nil
        )
    }

    static func partial(
        threads: [HyperlitePinnedCodexThread],
        unresolvedMetadataCount: Int,
        observedAt: Date
    ) -> HyperlitePinnedCodexThreadSnapshot {
        HyperlitePinnedCodexThreadSnapshot(
            availability: .partial,
            checkedAt: observedAt,
            observedAt: observedAt,
            threads: threads,
            unresolvedMetadataCount: unresolvedMetadataCount,
            message: HyperlitePinnedCodexThreadPresentation.unresolvedMessage(
                count: unresolvedMetadataCount
            )
        )
    }

    static func unavailable(
        checkedAt: Date,
        message: String
    ) -> HyperlitePinnedCodexThreadSnapshot {
        HyperlitePinnedCodexThreadSnapshot(
            availability: .unavailable,
            checkedAt: checkedAt,
            observedAt: nil,
            threads: [],
            unresolvedMetadataCount: 0,
            message: message
        )
    }
}

struct HyperlitePinnedCodexThreadIndicatorPresentation: Equatable {
    let systemImage: String
    let countText: String
    let isMuted: Bool
    let accessibilityLabel: String
    let help: String
}

enum HyperlitePinnedCodexThreadPresentation {
    static func indicator(
        snapshot: HyperlitePinnedCodexThreadSnapshot?,
        lastAvailableAt: Date?,
        timeZone: TimeZone = .current
    ) -> HyperlitePinnedCodexThreadIndicatorPresentation {
        guard let snapshot else {
            return HyperlitePinnedCodexThreadIndicatorPresentation(
                systemImage: "pin",
                countText: "—",
                isMuted: true,
                accessibilityLabel: "Pinned Codex threads loading",
                help: "Loading pinned Codex threads"
            )
        }

        switch snapshot.availability {
        case .current:
            let count = snapshot.threads.count
            return HyperlitePinnedCodexThreadIndicatorPresentation(
                systemImage: count == 0 ? "pin" : "pin.fill",
                countText: "\(count)",
                isMuted: count == 0,
                accessibilityLabel: accessibilityCount(count),
                help: "\(countLabel(count)); \(observationLabel(snapshot.observedAt, timeZone: timeZone))"
            )
        case .partial:
            let count = snapshot.threads.count
            return HyperlitePinnedCodexThreadIndicatorPresentation(
                systemImage: count == 0 ? "pin" : "pin.fill",
                countText: "\(count)",
                isMuted: false,
                accessibilityLabel: "\(accessibilityCount(count)), metadata partially available",
                help: "\(countLabel(count)); \(unresolvedMessage(count: snapshot.unresolvedMetadataCount)); " +
                    observationLabel(snapshot.observedAt, timeZone: timeZone)
            )
        case .unavailable:
            var help = snapshot.message ?? "Pinned Codex threads are unavailable"
            if let lastAvailableAt {
                help += "; last available \(timestamp(lastAvailableAt, timeZone: timeZone))"
            }
            return HyperlitePinnedCodexThreadIndicatorPresentation(
                systemImage: "pin.slash",
                countText: "—",
                isMuted: true,
                accessibilityLabel: "Pinned Codex threads unavailable",
                help: help
            )
        }
    }

    static func statusText(
        snapshot: HyperlitePinnedCodexThreadSnapshot?,
        lastAvailableAt: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let snapshot else { return "Loading pinned Codex threads…" }
        switch snapshot.availability {
        case .current:
            return "\(countLabel(snapshot.threads.count)) • " +
                observationLabel(snapshot.observedAt, timeZone: timeZone)
        case .partial:
            return "\(countLabel(snapshot.threads.count)) • " +
                "\(unresolvedMessage(count: snapshot.unresolvedMetadataCount)) • " +
                observationLabel(snapshot.observedAt, timeZone: timeZone)
        case .unavailable:
            guard let lastAvailableAt else {
                return snapshot.message ?? "Pinned Codex threads are unavailable"
            }
            return "\(snapshot.message ?? "Pinned Codex threads are unavailable") • " +
                "Last available \(timestamp(lastAvailableAt, timeZone: timeZone))"
        }
    }

    static func unresolvedMessage(count: Int) -> String {
        "\(count) pinned thread title\(count == 1 ? " is" : "s are") unavailable"
    }

    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func observationLabel(_ date: Date?, timeZone: TimeZone) -> String {
        guard let date else { return "Observation time unavailable" }
        return "Observed \(timestamp(date, timeZone: timeZone))"
    }

    private static func countLabel(_ count: Int) -> String {
        "\(count) pinned Codex thread\(count == 1 ? "" : "s")"
    }

    private static func accessibilityCount(_ count: Int) -> String {
        countLabel(count)
    }
}

enum HyperliteCodexFileState: Equatable, Sendable {
    case missing
    case other
    case unreadable
    case regular(inode: UInt64, size: Int64, mode: UInt32, seconds: Int64, nanoseconds: Int64)
}

struct HyperlitePinnedCodexThreadSourceSignature: Equatable, Sendable {
    let globalState: HyperliteCodexFileState
    let database: HyperliteCodexFileState
    let databaseWAL: HyperliteCodexFileState
}

enum HyperlitePinnedCodexThreadLoadResult: Equatable {
    case unchanged(HyperlitePinnedCodexThreadSourceSignature)
    case loaded(
        HyperlitePinnedCodexThreadSnapshot,
        HyperlitePinnedCodexThreadSourceSignature
    )
}
