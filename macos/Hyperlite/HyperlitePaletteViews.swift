import AppKit
import SwiftUI

struct HyperliteCommandPalette: View {
    let mode: HyperlitePaletteMode
    let items: [HyperliteWorkItem]
    let errors: [HyperliteDiagnostic]
    let warnings: [HyperliteDiagnostic]
    let onAction: (HyperlitePaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var expandedProjects: Set<String> = []
    @State private var selection = 0

    private var entries: [HyperlitePaletteEntry] {
        switch mode {
        case .commands:
            HyperliteInteractionModel.commandEntries(
                items: items,
                errors: errors,
                warnings: warnings
            )
        case .projects:
            HyperliteInteractionModel.projectEntries(
                items: items,
                expandedProjects: expandedProjects
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(mode == .commands ? "Commands" : "Projects",
                      systemImage: mode == .commands ? "command" : "folder")
                    .font(.headline)
                Spacer()
                Text(mode == .commands ? "⌘K" : "⌘P")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            entryList
            Divider()
            HStack(spacing: 12) {
                Text("↑↓ / J K navigate")
                if mode == .projects { Text("Space expand") }
                Text("Enter select")
                Spacer()
                Text("Esc close")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(10)
        }
        .frame(width: 420, height: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .background(HyperliteKeyCapture(onKeyDown: handleKey))
        .onExitCommand(perform: onDismiss)
        .onChange(of: entries.count) { count in
            selection = HyperliteInteractionModel.movedSelection(selection, by: 0, count: count)
        }
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(entry, selected: index == selection)
                            .id(entry.id)
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { index in
                guard entries.indices.contains(index) else { return }
                proxy.scrollTo(entries[index].id, anchor: .center)
            }
        }
    }

    private func entryRow(_ entry: HyperlitePaletteEntry, selected: Bool) -> some View {
        Button {
            if let index = entries.firstIndex(of: entry) {
                selection = index
            }
            activate(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(isProject(entry) ? .bold : .semibold))
                        .lineLimit(1)
                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                selected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(disallowedModifiers).isEmpty {
            return false
        }
        switch event.keyCode {
        case 53:
            onDismiss()
        case 125:
            moveSelection(by: 1)
        case 126:
            moveSelection(by: -1)
        case 49:
            activateSpace()
        case 36, 76:
            activateSelectedEntry()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "j": moveSelection(by: 1)
            case "k": moveSelection(by: -1)
            default: return false
            }
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        selection = HyperliteInteractionModel.movedSelection(
            selection,
            by: delta,
            count: entries.count
        )
    }

    private func activateSpace() {
        guard entries.indices.contains(selection),
              case let .project(repositoryPath) = entries[selection].kind
        else { return }
        toggleProject(repositoryPath)
    }

    private func activateSelectedEntry() {
        guard entries.indices.contains(selection) else { return }
        activate(entries[selection])
    }

    private func activate(_ entry: HyperlitePaletteEntry) {
        switch entry.kind {
        case let .project(repositoryPath):
            toggleProject(repositoryPath)
        case let .action(action):
            onAction(action)
        }
    }

    private func toggleProject(_ repositoryPath: String) {
        if expandedProjects.contains(repositoryPath) {
            expandedProjects.remove(repositoryPath)
        } else {
            expandedProjects.insert(repositoryPath)
        }
    }

    private func isProject(_ entry: HyperlitePaletteEntry) -> Bool {
        if case .project = entry.kind { return true }
        return false
    }
}
