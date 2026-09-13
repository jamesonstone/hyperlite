import Foundation

enum HyperliteProjectCelestialKind: String, Equatable {
    case star
    case moon
    case planet
    case giant

    var diameter: CGFloat {
        switch self {
        case .star: 14
        case .moon: 18
        case .planet: 24
        case .giant: 32
        }
    }

    var listDiameter: CGFloat {
        switch self {
        case .star: 11
        case .moon: 13
        case .planet: 15
        case .giant: 17
        }
    }

    var spinPeriod: TimeInterval {
        switch self {
        case .star: 10
        case .moon: 16
        case .planet: 20
        case .giant: 28
        }
    }

    func emoji(for id: String) -> String {
        let pool: [String]
        switch self {
        case .star: pool = ["⭐️", "🌟"]
        case .moon: pool = ["🌕", "🌖", "🌗"]
        case .planet: pool = ["🌍", "🌎", "🌏"]
        case .giant: pool = ["🪐"]
        }
        let seed = id.unicodeScalars.reduce(UInt64(7)) { partial, scalar in
            partial &* 33 &+ UInt64(scalar.value)
        }
        return pool[Int(seed % UInt64(pool.count))]
    }
}

enum HyperliteProjectOrbitPresentation {
    static let sunEmoji = "☀️"
    static let sunSize: CGFloat = 28
    static let sunSpinPeriod: TimeInterval = 36
    static let revolutionPeriod: TimeInterval = 72
    static let inset: CGFloat = 36
    static let captionReserve: CGFloat = 28
    static let bodyClearance: CGFloat = 32
    static let hitSize: CGFloat = 36
    static let labelWidth: CGFloat = 56
    static let dragSlop: CGFloat = 4
    static var bodyHitSize: CGSize {
        CGSize(width: max(hitSize, 64), height: max(hitSize, 44))
    }
    /// Underdamped so a released body overshoots once, then settles.
    static let returnStiffness: Double = 170
    static let returnDamping: Double = 13

    static func classify(count: Int?) -> HyperliteProjectCelestialKind {
        guard let count, count > 0 else { return .star }
        switch count {
        case ..<200: return .star
        case ..<2000: return .moon
        case ..<20000: return .planet
        default: return .giant
        }
    }

    static func kinds(
        for projects: [HyperliteProjectPullRequests]
    ) -> [String: HyperliteProjectCelestialKind] {
        Dictionary(uniqueKeysWithValues: projects.map { project in
            (project.id, classify(count: project.commitCount))
        })
    }

    static func center(in size: CGSize) -> CGPoint {
        let usableHeight = max(size.height - captionReserve, 0)
        return CGPoint(x: size.width / 2, y: captionReserve + usableHeight / 2)
    }

    static func radius(in size: CGSize) -> CGFloat {
        let usableHeight = max(size.height - captionReserve, 0)
        return max(min(size.width, usableHeight) / 2 - bodyClearance, 12)
    }

    static func clampOffset(
        _ translation: CGSize,
        origin: CGPoint,
        in size: CGSize
    ) -> CGSize {
        let hit = bodyHitSize
        let halfW = hit.width / 2
        let halfH = hit.height / 2
        let minX = halfW
        let maxX = max(size.width - halfW, halfW)
        let minY = halfH
        let maxY = max(size.height - halfH, halfH)
        let x = min(max(origin.x + translation.width, minX), maxX)
        let y = min(max(origin.y + translation.height, minY), maxY)
        return CGSize(width: x - origin.x, height: y - origin.y)
    }

    static func sunAnchor(in size: CGSize) -> CGPoint {
        let origin = center(in: size)
        return CGPoint(
            x: origin.x / max(size.width, 1),
            y: origin.y / max(size.height, 1)
        )
    }

    static func bodyPoint(index: Int, count: Int, in size: CGSize) -> CGPoint {
        let total = max(count, 1)
        let angle = (Double(index) / Double(total)) * 2 * .pi - .pi / 2
        return polar(angle: angle, radius: radius(in: size), in: size)
    }

    static var returnSpringIsUnderdamped: Bool {
        returnDamping < 2 * returnStiffness.squareRoot()
    }

    private static func polar(angle: Double, radius: CGFloat, in size: CGSize) -> CGPoint {
        let origin = center(in: size)
        let point = CGPoint(
            x: origin.x + CGFloat(cos(angle)) * radius,
            y: origin.y + CGFloat(sin(angle)) * radius
        )
        return CGPoint(
            x: min(max(point.x, inset), max(size.width - inset, inset)),
            y: min(max(point.y, inset), max(size.height - inset, inset))
        )
    }
}
