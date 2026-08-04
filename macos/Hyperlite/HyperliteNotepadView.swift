import SwiftUI

private enum HyperliteCalendarPopoverLayout {
    // macOS keeps the graphical DatePicker compact, so scale it and reserve matching space.
    static let contentPadding: CGFloat = 14
    static let pickerScale: CGFloat = 2
    static let pickerWidth: CGFloat = 288
    static let pickerHeight: CGFloat = 310
    static let popoverWidth = pickerWidth + contentPadding * 2
}

struct HyperliteNotepadView: View {
    @ObservedObject var state: HyperliteNotepadState
    @State private var isCalendarPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            tabHeader
            switch state.activeTab {
            case .notepad:
                editorSurface(
                    text: state.pinnedText,
                    placeholder: "Project names, repository paths, commands, and identifiers",
                    accessibilityLabel: "Notepad",
                    focusTarget: .pinned,
                    onChange: state.updatePinned
                )
            case .daily:
                editorSurface(
                    text: state.dailyText,
                    placeholder: "Write this daily note — created when you begin typing",
                    accessibilityLabel: "Daily note for \(state.selectedDateIdentifier)",
                    focusTarget: .daily,
                    onChange: state.updateDaily
                )
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 5)
        .overlay(alignment: .top) { HyperliteThemeDivider() }
        .overlay(alignment: .bottom) { HyperliteThemeDivider() }
    }

    private var tabHeader: some View {
        HStack(spacing: 4) {
            calendarButton
            tabButton(
                isSelected: state.activeTab == .notepad,
                accessibilityLabel: "Notepad",
                action: state.focusPinned
            ) {
                Text("Notepad")
                    .font(HyperliteTypography.semibold(11))
            }
            Rectangle()
                .fill(HyperliteTheme.elevatedSurface.color)
                .frame(width: 1, height: 17)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)
            tabButton(
                isSelected: state.activeTab == .daily,
                accessibilityLabel: "Daily: \(state.displayName(for: state.selectedDateIdentifier))",
                action: state.focusDaily
            ) {
                HStack(spacing: 5) {
                    Text("Daily:")
                        .font(HyperliteTypography.semibold(11))
                    Text(state.displayName(for: state.selectedDateIdentifier))
                        .font(HyperliteTypography.regular(10))
                }
            }
            Spacer(minLength: 6)
            saveStatus
        }
        .frame(minHeight: 24)
    }

    private var calendarButton: some View {
        Button {
            isCalendarPresented.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(HyperliteTypography.semibold(13))
                .foregroundStyle(HyperliteTheme.blue.color)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isNavigating)
        .help("Choose a daily note date")
        .accessibilityLabel("Open daily note calendar")
        .popover(isPresented: $isCalendarPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily note date")
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(HyperliteTheme.primaryText.color)
                DatePicker(
                    "Select daily note date",
                    selection: Binding(
                        get: { state.selectedDate },
                        set: { date in
                            isCalendarPresented = false
                            Task { await state.selectDate(date, focus: true) }
                        }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .fixedSize()
                .scaleEffect(
                    HyperliteCalendarPopoverLayout.pickerScale,
                    anchor: .topLeading
                )
                .frame(
                    width: HyperliteCalendarPopoverLayout.pickerWidth,
                    height: HyperliteCalendarPopoverLayout.pickerHeight,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(state.isNavigating)
            }
            .padding(HyperliteCalendarPopoverLayout.contentPadding)
            .frame(width: HyperliteCalendarPopoverLayout.popoverWidth)
            .hyperliteTheme()
        }
    }

    private func tabButton<Label: View>(
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    isSelected
                        ? HyperliteTheme.primaryText.color
                        : HyperliteTheme.secondaryText.color
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    isSelected
                        ? HyperliteTheme.elevatedSurface.color.opacity(0.65)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle()
                            .fill(HyperliteTheme.cyan.color)
                            .frame(height: 2)
                            .padding(.horizontal, 5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isNavigating)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
}
