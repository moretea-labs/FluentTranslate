#if os(macOS)
import AppKit
import SwiftUI

struct SubmitTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusRequestID: Int
    let onSubmit: () -> Void
    let onAccurateSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ActionTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = .systemFont(ofSize: 19)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .clear
        textView.string = text
        textView.onSubmit = onSubmit
        textView.onAccurateSubmit = onAccurateSubmit
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async {
            // Both workspace and quick panel share an AppModel. Only the
            // active window may claim input focus.
            guard let window = textView.window, window.isKeyWindow else { return }
            window.makeFirstResponder(textView)
            context.coordinator.isFocused.wrappedValue = true
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ActionTextView else { return }
        textView.onSubmit = onSubmit
        textView.onAccurateSubmit = onAccurateSubmit
        context.coordinator.isFocused = $isFocused
        // An active CJK input method owns its marked text. Replacing its
        // storage during composition causes duplicate/overlapping glyphs.
        if textView.string != text && !textView.hasMarkedText() {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, text.utf16.count), length: 0))
        }
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                guard let window = textView.window, window.isKeyWindow else { return }
                window.makeFirstResponder(textView)
                textView.selectAll(nil)
                context.coordinator.isFocused.wrappedValue = true
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        var isFocused: Binding<Bool>
        var lastFocusRequestID = 0

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class ActionTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onAccurateSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn else {
            super.keyDown(with: event)
            return
        }

        // Let the input method commit its marked text before treating Return as submit.
        // Without this guard, confirming a Chinese IME candidate can submit prematurely.
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.shift) {
            insertNewline(nil)
        } else if event.modifierFlags.contains(.command) {
            onAccurateSubmit?()
        } else {
            onSubmit?()
        }
    }
}
#endif
