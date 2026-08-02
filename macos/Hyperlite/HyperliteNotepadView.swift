import SwiftUI

struct HyperliteNotepadView: View {
    @ObservedObject var state: HyperliteNotepadState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            notepadHeader
            editorSurface(
                text: state.pinnedText,
                placeholder: "Project names, repository paths, commands, and identifiers",
                accessibilityLabel: "Pinned note",
                focusTarget: .pinned,
                onChange: state.updatePinned
            )
            dailyHeader
            editorSurface(
                text: state.dailyText,
                placeholder: "Write this daily note — created when you begin typing",
                accessibilityLabel: "Daily note for \(state.selectedDateIdentifier)",
                focusTarget: .daily,
                onChange: state.updateDaily
            )
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 5)
        .overlay(alignment: .top) { HyperliteThemeDivider() }
        .overlay(alignment: .bottom) { HyperliteThemeDivider() }
    }

    private var notepadHeader: some View {
        HStack(spacing: 6) {
            Menu {
                recentButton("Today", date: state.todayIdentifier)
                recentButton("Yesterday", date: state.yesterdayIdentifier)
                let recent = Array(state.recentDailyNotes.filter {
                    $0.date != state.todayIdentifier && $0.date != state.yesterdayIdentifier
                }.prefix(HyperliteNotepadState.maximumRecentNotes))
                if !recent.isEmpty {
                    Divider()
                    ForEach(recent) { note in
                        recentButton(state.displayName(for: note.date), date: note.date)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Notepad")
                    Image(systemName: "chevron.down")
                        .font(HyperliteTypography.semibold(8))
                }
                .font(HyperliteTypography.semibold(11))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Open recent daily notes")
            noteLabel("Pinned", symbol: "pin.fill")
            Spacer()
            saveStatus
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if state.isSaving {
            ProgressView()
                .controlSize(.mini)
                .tint(HyperliteTheme.cyan.color)
                .accessibilityLabel("Saving notes")
        } else if let error = state.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.red.color)
                .lineLimit(1)
                .help(error)
        }
    }

    private var dailyHeader: some View {
        HStack(spacing: 5) {
            noteLabel("Daily", symbol: "calendar")
            Text(state.displayName(for: state.selectedDateIdentifier))
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .lineLimit(1)
            Spacer(minLength: 4)
            navigationButton("chevron.left", help: "Previous day") {
                await state.selectPreviousDay()
            }
            Button("Today") { Task { await state.selectToday() } }
                .buttonStyle(.borderless)
                .font(HyperliteTypography.semibold(9))
                .disabled(state.isTodaySelected || state.isNavigating)
                .help("Return to today")
            navigationButton("chevron.right", help: "Next day") {
                await state.selectNextDay()
            }
            DatePicker(
                "Select daily note date",
                selection: Binding(
                    get: { state.selectedDate },
                    set: { date in Task { await state.selectDate(date) } }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .disabled(state.isNavigating)
            .fixedSize()
        }
    }

    private func noteLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(HyperliteTypography.semibold(10))
            .foregroundStyle(HyperliteTheme.secondaryText.color)
    }

    private func editorSurface(
        text: String,
        placeholder: String,
        accessibilityLabel: String,
        focusTarget: HyperliteNotepadFocusRequest.Target,
        onChange: @escaping (String, Int?) -> Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            HyperlitePlainTextEditor(
                text: text,
                maxBytes: HyperliteNotepadState.maxBytes,
                accessibilityLabel: accessibilityLabel,
                focusGeneration: state.focusRequest?.target == focusTarget
                    ? state.focusRequest?.generation
                    : nil,
                onChange: { content, byteCount in _ = onChange(content, byteCount) }
            )
            if text.isEmpty {
                Text(placeholder)
                    .font(HyperliteTypography.regular(11))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: HyperliteWorkspaceSizing.minimumNotepadEditorHeight, maxHeight: .infinity)
        .background(
            HyperliteTheme.canvas.color,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(HyperliteTheme.elevatedSurface.color, lineWidth: 1)
        }
        .disabled(state.isNavigating)
    }

    private func recentButton(_ title: String, date: String) -> some View {
        Button(title) { Task { await state.selectDateIdentifier(date, focus: true) } }
    }

    private func navigationButton(
        _ symbol: String,
        help: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(state.isNavigating)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
