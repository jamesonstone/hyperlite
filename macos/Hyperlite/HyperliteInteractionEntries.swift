import Foundation

extension HyperliteInteractionModel {
    static func projectSummary(pullRequestCount: Int, laneCount: Int) -> String {
        "\(pullRequestCount) PR\(pullRequestCount == 1 ? "" : "s") · " +
            "\(laneCount) lane\(laneCount == 1 ? "" : "s")"
    }

    static func actionEntry(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ action: HyperlitePaletteAction
    ) -> HyperlitePaletteEntry {
        HyperlitePaletteEntry(
            id: id, title: title, subtitle: subtitle, symbol: symbol, kind: .action(action)
        )
    }
}
