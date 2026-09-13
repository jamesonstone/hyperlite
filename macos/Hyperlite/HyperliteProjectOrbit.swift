import Foundation

enum HyperliteProjectCelestialKind: String, Equatable {
    case star
    case moon
    case planet
    case giant

    var diameter: CGFloat {
        switch self {
        case .star: 8
        case .moon: 13
        case .planet: 20
        case .giant: 28
        }
    }

    var listDiameter: CGFloat {
        switch self {
        case .star: 7
        case .moon: 9
        case .planet: 12
        case .giant: 15
        }
    }

    var symbolName: String {
        switch self {
        case .star: "star.fill"
        case .moon: "moon.fill"
        case .planet: "circle.fill"
        case .giant: "globe.americas.fill"
        }
    }
}

enum HyperliteProjectOrbitPresentation {
    static let sunSize: CGFloat = 26
    static let cometCount = 3
    static let period: TimeInterval = 56
    static let tickInterval: TimeInterval = 1.0 / 12.0
    static let inset: CGFloat = 36
    static let hitSize: CGFloat = 36
    static let labelWidth: CGFloat = 56

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
        CGPoint(x: size.width / 2, y: size.height / 2 + 6)
    }

    static func radius(in size: CGSize) -> CGFloat {
        max(min(size.width, size.height) * 0.38, 28)
    }

    static func phase(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        var elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        if elapsed < 0 { elapsed += period }
        return elapsed / period * 2 * .pi
    }

    static func bodyPoint(
        index: Int,
        count: Int,
        in size: CGSize,
        phase: Double
    ) -> CGPoint {
        let total = max(count, 1)
        let angle = (Double(index) / Double(total)) * 2 * .pi - .pi / 2 + phase
        return polar(angle: angle, radius: radius(in: size), in: size)
    }

    static func cometPoint(
        index: Int,
        at date: Date,
        in size: CGSize,
        reduceMotion: Bool
    ) -> CGPoint {
        let instant = reduceMotion ? Date(timeIntervalSinceReferenceDate: 0) : date
        let period = 11.0 + Double(index) * 5.0
        var elapsed = instant.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        if elapsed < 0 { elapsed += period }
        let angle = elapsed / period * 2 * .pi + Double(index) * 1.7
        let orbit = radius(in: size) * (0.22 + CGFloat(index) * 0.09)
        return polar(angle: angle, radius: orbit, in: size)
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
