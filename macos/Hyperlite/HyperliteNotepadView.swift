import AppKit
import SwiftUI

struct HyperliteNotepadView: View {
    @ObservedObject var state: HyperliteNotepadState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Notepad")
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                Spacer()
                if state.isSaving {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(HyperliteTheme.cyan.color)
                        .accessibilityLabel("Saving notepad")
                } else if let error = state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.red.color)
                        .lineLimit(1)
                        .help(error)
                }
            }

            ZStack(alignment: .topLeading) {
                HyperlitePlainTextEditor(
                    text: state.text,
                    maxBytes: HyperliteNotepadState.maxBytes,
                    onChange: { text, byteCount in
                        _ = state.update(text, byteCount: byteCount)
                    }
                )
                if state.text.isEmpty {
                    Text("Write anything — local only")
                        .font(.system(size: 13))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(
                minHeight: HyperliteWorkspaceSizing.minimumNotepadEditorHeight,
                maxHeight: .infinity
            )
            .background(
                HyperliteTheme.surface.color,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(HyperliteTheme.elevatedSurface.color, lineWidth: 1)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { HyperliteThemeDivider() }
        .overlay(alignment: .bottom) { HyperliteThemeDivider() }
    }
}

private struct HyperlitePlainTextEditor: NSViewRepresentable {
    let text: String
    let maxBytes: Int
    let onChange: (String, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView(frame: .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = HyperliteTypography.plainTextAppKitFont(13)
        textView.textColor = HyperliteTheme.primaryText.appKitColor
        textView.insertionPointColor = HyperliteTheme.blue.appKitColor
        textView.selectedTextAttributes = [
            .backgroundColor: HyperliteTheme.blue.appKitColor.withAlphaComponent(0.53),
            .foregroundColor: HyperliteTheme.primaryText.appKitColor,
        ]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 3, height: 3)
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityLabel("Notepad")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(selection.location, textView.string.utf16.count),
            length: 0
        ))
        context.coordinator.byteCount = text.utf8.count
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HyperlitePlainTextEditor
        var byteCount: Int
        private var pendingByteCount: Int?

        init(parent: HyperlitePlainTextEditor) {
            self.parent = parent
            byteCount = parent.text.utf8.count
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let source = textView.string as NSString
            guard affectedCharRange.location + affectedCharRange.length <= source.length else {
                return false
            }
            let removedBytes = source.substring(with: affectedCharRange).utf8.count
            let insertedBytes = (replacementString ?? "").utf8.count
            let candidateByteCount = byteCount - removedBytes + insertedBytes
            guard candidateByteCount <= parent.maxBytes else {
                NSSound.beep()
                return false
            }
            pendingByteCount = candidateByteCount
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            byteCount = pendingByteCount ?? textView.string.utf8.count
            pendingByteCount = nil
            parent.onChange(textView.string, byteCount)
        }
    }
}
