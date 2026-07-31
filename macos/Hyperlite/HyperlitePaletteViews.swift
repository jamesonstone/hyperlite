import AppKit
import SwiftUI

struct HyperliteCommandPalette: View {
    let mode: HyperlitePaletteMode
    let threads: [HyperliteThread]
    let projects: [HyperliteProjectLocation]
    let pullRequests: HyperliteProjectPullRequestScan?
    let onAction: (HyperlitePaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var expandedProjects: Set<String> = []
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var unfilteredEntries: [HyperlitePaletteEntry] {
        switch mode {
        case .commands:
            return HyperliteInteractionModel.commandEntries(threads: threads)
        case .projects:
            let effectiveExpansion = HyperliteInteractionModel.effectiveProjectExpansion(
                projects: projects,
                expandedProjects: expandedProjects,
                query: query
            )
            return HyperliteInteractionModel.projectEntries(
                projects: projects,
                pullRequests: pullRequests,
                expandedProjects: effectiveExpansion
            )
        case .removeProjects:
            return HyperliteInteractionModel.removeProjectEntries(projects: projects)
        }
    }

    private var entries: [HyperlitePaletteEntry] {
        HyperliteInteractionModel.filteredEntries(unfilteredEntries, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paletteHeader
            paletteDivider
            entryList
            paletteDivider
            HStack(spacing: 12) {
                Text("↑↓ navigate")
                Text("Enter select")
                Spacer()
                Text("Esc close")
            }
            .font(HyperliteTypography.regular(10))
            .foregroundStyle(HyperlitePaletteTheme.mutedText.color)
            .padding(10)
            .background(HyperlitePaletteTheme.canvas.color.opacity(0.38))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(HyperlitePaletteTheme.primaryText.color)
        .background(
            HyperlitePaletteTheme.surface.color,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HyperlitePaletteTheme.mutedText.color.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        .shadow(color: HyperlitePaletteTheme.blue.color.opacity(0.14), radius: 9, y: 2)
        .environment(\.colorScheme, .dark)
        .background(HyperliteKeyCapture(onKeyDown: handleKey))
        .onExitCommand(perform: onDismiss)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _ in selection = 0 }
        .onChange(of: entries.count) { count in
            selection = HyperliteInteractionModel.movedSelection(selection, by: 0, count: count)
        }
    }

    private var paletteHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(paletteTitle, systemImage: paletteSymbol)
                    .font(HyperliteTypography.semibold(13))
                    .foregroundStyle(HyperlitePaletteTheme.primaryText.color)
                Spacer()
                Text(shortcutLabel)
                    .font(HyperliteTypography.regular(11))
                    .foregroundStyle(HyperlitePaletteTheme.mutedText.color)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HyperlitePaletteTheme.cyan.color)
                TextField(
                    "",
                    text: $query,
                    prompt: Text(searchPrompt)
                        .foregroundColor(HyperlitePaletteTheme.mutedText.color)
                )
                    .textFieldStyle(.plain)
                    .font(HyperliteTypography.regular(12))
                    .foregroundStyle(HyperlitePaletteTheme.primaryText.color)
                    .tint(HyperlitePaletteTheme.blue.color)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HyperlitePaletteTheme.mutedText.color)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                HyperlitePaletteTheme.elevatedSurface.color,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        HyperlitePaletteTheme.cyan.color.opacity(searchFocused ? 0.72 : 0.3),
                        lineWidth: 1
                    )
            }
        }
        .padding(12)
        .background(HyperlitePaletteTheme.surface.color)
    }

    private var paletteTitle: String {
        switch mode {
        case .commands: "Commands"
        case .projects: "Projects"
        case .removeProjects: "Remove Project"
        }
    }

    private var paletteSymbol: String {
        mode == .commands ? "command" : "folder"
    }

    private var shortcutLabel: String {
        switch mode {
        case .commands, .removeProjects: "⌘K"
        case .projects: "⌘P"
        }
    }

    private var searchPrompt: String {
        switch mode {
        case .commands: "Search commands"
        case .projects: "Search projects, PRs, and worktrees"
        case .removeProjects: "Search configured projects"
        }
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if entries.isEmpty {
                    Text(query.isEmpty ? "No configured projects" : "No matches")
                        .font(HyperliteTypography.regular(11))
                        .foregroundStyle(HyperlitePaletteTheme.mutedText.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry, selected: index == selection)
                                .id(entry.id)
                                .onHover { if $0 { selection = index } }
                        }
                    }
                    .padding(8)
                }
            }
            .onChange(of: selection) { index in
                guard entries.indices.contains(index) else { return }
                proxy.scrollTo(entries[index].id, anchor: .center)
            }
        }
    }

    private func entryRow(_ entry: HyperlitePaletteEntry, selected: Bool) -> some View {
        Button {
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { selection = index }
            activate(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.symbol)
                    .font(HyperliteTypography.semibold(13))
                    .foregroundStyle(
                        selected
                            ? HyperlitePaletteTheme.primaryText.color
                            : HyperlitePaletteTheme.cyan.color
                    )
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(
                            isProject(entry)
                                ? HyperliteTypography.bold(12)
                                : HyperliteTypography.semibold(12)
                        )
                        .lineLimit(1)
                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(HyperliteTypography.regular(11))
                            .foregroundStyle(HyperlitePaletteTheme.secondaryText.color)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                selected ? HyperlitePaletteTheme.blue.color.opacity(0.53) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.isDisjoint(with: disallowedModifiers) { return false }
        switch event.keyCode {
        case 53: onDismiss()
        case 125: moveSelection(by: 1)
        case 126: moveSelection(by: -1)
        case 36, 76: activateSelectedEntry()
        default: return false
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        selection = HyperliteInteractionModel.movedSelection(selection, by: delta, count: entries.count)
    }

    private func activateSelectedEntry() {
        guard entries.indices.contains(selection) else { return }
        activate(entries[selection])
    }

    private func activate(_ entry: HyperlitePaletteEntry) {
        switch entry.kind {
        case let .project(project): toggleProject(project)
        case let .action(action): onAction(action)
        }
    }

    private func toggleProject(_ project: String) {
        if expandedProjects.contains(project) {
            expandedProjects.remove(project)
        } else {
            expandedProjects.insert(project)
        }
    }

    private func isProject(_ entry: HyperlitePaletteEntry) -> Bool {
        if case .project = entry.kind { return true }
        return false
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(HyperlitePaletteTheme.mutedText.color.opacity(0.32))
            .frame(height: 1)
    }
}
