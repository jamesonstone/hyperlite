import Foundation

enum HyperlitePaletteMode: String, Hashable, Identifiable {
    case commands
    case projects

    var id: String { rawValue }
}

enum HyperlitePaletteAction: Equatable {
    case refresh
    case settings
    case diagnostics
    case prune(HyperliteDiagnostic)
    case reveal(String)
}

struct HyperlitePaletteEntry: Equatable, Identifiable {
    enum Kind: Equatable {
        case action(HyperlitePaletteAction)
        case project(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let kind: Kind
}

enum HyperliteInteractionModel {
    static func commandEntries(
        items: [HyperliteWorkItem],
        errors: [HyperliteDiagnostic],
        warnings: [HyperliteDiagnostic]
    ) -> [HyperlitePaletteEntry] {
        var entries = [
            actionEntry("action:refresh", "Refresh", "Refresh Git and pull request status", "arrow.clockwise", .refresh),
            actionEntry("action:settings", "Settings", "Open Hyperlite settings", "gearshape.fill", .settings),
        ]
        let diagnostics = errors + warnings
        if !diagnostics.isEmpty {
            entries.append(actionEntry(
                "action:diagnostics",
                "Diagnostics",
                diagnosticCountSummary(errors: errors.count, warnings: warnings.count),
                errors.isEmpty ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
                .diagnostics
            ))
        }
        for diagnostic in warnings where diagnostic.isPrunableWorktree {
            entries.append(actionEntry(
                "prune:\(diagnostic.id)",
                "Prune stale worktree metadata",
                compactDiagnostic(diagnostic),
                "trash.slash",
                .prune(diagnostic)
            ))
        }
        entries.append(contentsOf: items.map { item in
            actionEntry(
                "item:\(item.id)",
                hoverTitle(for: item),
                hoverSummary(for: item),
                item.statuses.first?.symbol ?? "circle.fill",
                .reveal(item.id)
            )
        })
        return entries
    }

    static func projectEntries(
        items: [HyperliteWorkItem],
        expandedProjects: Set<String>
    ) -> [HyperlitePaletteEntry] {
        var orderedProjects: [String] = []
        var groupedItems: [String: [HyperliteWorkItem]] = [:]
        for item in items {
            if groupedItems[item.repositoryPath] == nil {
                orderedProjects.append(item.repositoryPath)
            }
            groupedItems[item.repositoryPath, default: []].append(item)
        }

        var entries: [HyperlitePaletteEntry] = []
        for repositoryPath in orderedProjects {
            guard let projectItems = groupedItems[repositoryPath], let first = projectItems.first else { continue }
            let expanded = expandedProjects.contains(repositoryPath)
            entries.append(HyperlitePaletteEntry(
                id: "project:\(repositoryPath)",
                title: first.repository,
                subtitle: "\(projectItems.count) item\(projectItems.count == 1 ? "" : "s")",
                symbol: expanded ? "chevron.down" : "chevron.right",
                kind: .project(repositoryPath)
            ))
            if expanded {
                entries.append(contentsOf: projectItems.map { item in
                    HyperlitePaletteEntry(
                        id: "item:\(item.id)",
                        title: item.title,
                        subtitle: hoverSummary(for: item),
                        symbol: item.statuses.first?.symbol ?? "circle.fill",
                        kind: .action(.reveal(item.id))
                    )
                })
            }
        }
        return entries
    }

    static func movedSelection(_ selection: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selection + delta, 0), count - 1)
    }

    static func hoverTitle(for item: HyperliteWorkItem) -> String {
        truncated("\(item.repository) · \(item.title)", limit: 120)
    }

    static func hoverSummary(for item: HyperliteWorkItem) -> String {
        let status = item.statuses.map(\.label).joined(separator: ", ")
        let action: String
        if item.pullRequest != nil {
            action = "Open the pull request from the main list."
        } else {
            action = "Copy \(item.clickPath) from the main list."
        }
        return truncated("\(status). \(action)", limit: 300)
    }

    static func compactDiagnostic(_ diagnostic: HyperliteDiagnostic) -> String {
        truncated(
            "\(diagnostic.repository) (\(diagnostic.stage)): \(diagnostic.message)",
            limit: 300
        )
    }

    static func truncated(_ value: String, limit: Int) -> String {
        guard limit > 0, value.count > limit else { return limit > 0 ? value : "" }
        if limit == 1 { return "…" }
        return String(value.prefix(limit - 1)) + "…"
    }

    static func diagnosticCountSummary(errors: Int, warnings: Int) -> String {
        var parts: [String] = []
        if errors > 0 {
            parts.append("\(errors) error\(errors == 1 ? "" : "s")")
        }
        if warnings > 0 {
            parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }

    private static func actionEntry(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ action: HyperlitePaletteAction
    ) -> HyperlitePaletteEntry {
        HyperlitePaletteEntry(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            kind: .action(action)
        )
    }
}
