import AppKit
import SwiftUI

struct HyperlitePlainTextEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled

    let text: String
    let maxBytes: Int
    let accessibilityLabel: String
    let focusGeneration: Int?
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
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.font = HyperliteTypography.editorAppKitFont()
        textView.textColor = HyperliteTheme.primaryText.appKitColor
        textView.insertionPointColor = HyperliteTheme.blue.appKitColor
        textView.selectedTextAttributes = [
            .backgroundColor: HyperliteTheme.blue.appKitColor.withAlphaComponent(0.53),
            .foregroundColor: HyperliteTheme.colorScheme == .light
                ? HyperliteTheme.primaryText.appKitColor
                : NSColor.white,
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
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.applyFocus(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, textView.string.utf16.count),
                length: 0
            ))
            context.coordinator.byteCount = text.utf8.count
        }
        context.coordinator.applyFocus(to: textView)
        textView.font = HyperliteTypography.editorAppKitFont()
        textView.textColor = HyperliteTheme.primaryText.appKitColor
        textView.insertionPointColor = HyperliteTheme.blue.appKitColor
        textView.selectedTextAttributes = [
            .backgroundColor: HyperliteTheme.blue.appKitColor.withAlphaComponent(0.53),
            .foregroundColor: HyperliteTheme.colorScheme == .light
                ? HyperliteTheme.primaryText.appKitColor
                : NSColor.white,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HyperlitePlainTextEditor
        var byteCount: Int
        private var pendingByteCount: Int?
        private var appliedFocusGeneration: Int?

        init(parent: HyperlitePlainTextEditor) {
            self.parent = parent
            byteCount = parent.text.utf8.count
        }

        func applyFocus(to textView: NSTextView) {
            guard let generation = parent.focusGeneration,
                  generation != appliedFocusGeneration
            else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let textView, let window = textView.window,
                      window.makeFirstResponder(textView)
                else { return }
                self?.appliedFocusGeneration = generation
            }
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
