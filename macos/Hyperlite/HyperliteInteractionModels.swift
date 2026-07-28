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
        threads: [HyperliteThread],
        errors: [HyperliteDiagnostic],
        warnings: [HyperliteDiagnostic]
    ) -> [HyperlitePaletteEntry] {
        var entries = [
            actionEntry("action:refresh", "Refresh", "Refresh local and GitHub evidence", "arrow.clockwise", .refresh),
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
        entries.append(contentsOf: threads.map { thread in
            actionEntry(
                "thread:\(thread.id)",
                hoverTitle(for: thread),
                hoverSummary(for: thread),
                thread.phase.symbol,
                .reveal(thread.id)
            )
        })
        return entries
    }

    static func projectEntries(
        threads: [HyperliteThread],
        expandedProjects: Set<String>
    ) -> [HyperlitePaletteEntry] {
        var order: [String] = []
        var grouped: [String: [HyperliteThread]] = [:]
        for thread in threads {
            let project = thread.repositories.first ?? "unknown"
            if grouped[project] == nil { order.append(project) }
            grouped[project, default: []].append(thread)
        }

        var entries: [HyperlitePaletteEntry] = []
        for project in order {
            guard let projectThreads = grouped[project] else { continue }
            let expanded = expandedProjects.contains(project)
            entries.append(HyperlitePaletteEntry(
                id: "project:\(project)",
                title: projectThreads.first?.projectName ?? "Unknown project",
                subtitle: "\(projectThreads.count) thread\(projectThreads.count == 1 ? "" : "s")",
                symbol: expanded ? "chevron.down" : "chevron.right",
                kind: .project(project)
            ))
            if expanded {
                entries.append(contentsOf: projectThreads.map { thread in
                    HyperlitePaletteEntry(
                        id: "thread:\(thread.id)",
                        title: thread.title,
                        subtitle: hoverSummary(for: thread),
                        symbol: thread.phase.symbol,
                        kind: .action(.reveal(thread.id))
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

    static func hoverTitle(for thread: HyperliteThread) -> String {
        truncated("\(thread.projectName) · \(thread.title)", limit: 120)
    }

    static func hoverSummary(for thread: HyperliteThread) -> String {
        truncated("\(thread.phase.label). \(thread.whyNow)", limit: 300)
    }

    static func compactDiagnostic(_ diagnostic: HyperliteDiagnostic) -> String {
        truncated("\(diagnostic.repository) (\(diagnostic.stage)): \(diagnostic.message)", limit: 300)
    }

    static func truncated(_ value: String, limit: Int) -> String {
        guard limit > 0, value.count > limit else { return limit > 0 ? value : "" }
        if limit == 1 { return "…" }
        return String(value.prefix(limit - 1)) + "…"
    }

    static func diagnosticCountSummary(errors: Int, warnings: Int) -> String {
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        return parts.joined(separator: " and ")
    }

    private static func actionEntry(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ action: HyperlitePaletteAction
    ) -> HyperlitePaletteEntry {
        HyperlitePaletteEntry(id: id, title: title, subtitle: subtitle, symbol: symbol, kind: .action(action))
    }
}
