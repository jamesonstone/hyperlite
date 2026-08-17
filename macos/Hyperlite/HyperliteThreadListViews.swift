import AppKit
import SwiftUI

struct HyperliteSectionHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Attention")
                .font(HyperliteTypography.bold(11))
                .foregroundStyle(HyperliteTheme.orange.color)
            Text("\(count)")
                .font(HyperliteTypography.bold(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            Spacer()
        }
        .padding(.top, 5)
    }
}

struct HyperliteSettingsView: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey
    @AppStorage("hyperlite.agent-session-sounds") private var agentSounds = false
    @AppStorage("hyperlite.agent-session-notifications") private var agentNotifications = false

    var body: some View {
        Form {
            Section("Shortcut") {
                TextField("Hot key", text: $hotkey)
                Text("Default: \(defaultHotKey). Use modifier names joined with +, for example Command+Shift+H.")
                    .font(HyperliteTypography.regular(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            Section("Projects") {
                Button("Add Project…") {
                    guard let path = HyperliteProjectPicker.selectProject() else { return }
                    state.addProject(path: path)
                }
                .disabled(state.isUpdatingProjects)
                if state.isUpdatingProjects {
                    ProgressView("Updating project configuration…")
                        .controlSize(.small)
                }
                if let error = state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.red.color)
                        .lineLimit(2)
                        .help(error)
                }
            }
            if HyperliteFeatureFlags.agentSessionPresentation {
                Section("Agent Sessions") {
                    Toggle("Play event sounds", isOn: $agentSounds)
                    Toggle("Show metadata-only notifications", isOn: $agentNotifications)
                        .onChange(of: agentNotifications) { enabled in
                            if enabled { HyperliteAgentAlerts.requestAuthorization() }
                        }
                    Text("Notifications contain only the client profile and project name.")
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.secondaryText.color)
                }
            }
            Section {
                Button("Quit Hyperlite") { NSApp.terminate(nil) }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}

struct HyperliteThreadRow: View {
    let thread: HyperliteThread
    let highlighted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: thread.hasUnseenAttention ? "exclamationmark.bubble.fill" : thread.phase.symbol)
                    .font(HyperliteTypography.bold(18))
                    .foregroundStyle(
                        thread.hasUnseenAttention
                            ? HyperliteTheme.orange.color
                            : HyperliteTheme.cyan.color
                    )
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(thread.title)
                            .font(HyperliteTypography.bold(15))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(HyperlitePresentation.ageLabel(for: thread.updatedAt))
                            .font(HyperliteTypography.semibold(11).monospacedDigit())
                            .foregroundStyle(HyperliteTheme.secondaryText.color)
                    }
                    HStack(spacing: 5) {
                        Text(thread.projectName)
                        Text("·")
                        Label(thread.phase.label, systemImage: thread.phase.symbol)
                    }
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    if let summary = HyperlitePresentation.rowSummary(for: thread) {
                        Text(summary)
                            .font(HyperliteTypography.regular(12))
                            .foregroundStyle(HyperliteTheme.primaryText.color)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                highlighted ? HyperliteTheme.blue.color.opacity(0.28) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .help("Open the inferred thread and its supporting evidence.")
        .hyperliteHoverPopover { HyperliteThreadHoverCard(thread: thread) }
    }
}
