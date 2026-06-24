import AppKit
import SwiftUI

/// A multiline macOS text editor that submits on Return while preserving
/// Shift+Return and Option+Return for inserting newlines.
struct SubmitTextEditor: NSViewRepresentable {
    @Binding var text: String
    let submitEnabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, submitEnabled: submitEnabled, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SubmitNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }

        context.coordinator.textView = textView
        scrollView.documentView = textView
        requestInitialFocus(for: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.textBinding = $text
        context.coordinator.submitEnabled = submitEnabled
        context.coordinator.onSubmit = onSubmit

        guard let textView = scrollView.documentView as? SubmitNSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges.compactMap { value in
                let range = value.rangeValue
                let boundedLocation = min(range.location, (text as NSString).length)
                let remainingLength = (text as NSString).length - boundedLocation
                return NSValue(range: NSRange(location: boundedLocation, length: min(range.length, remainingLength)))
            }
        }
        requestInitialFocus(for: textView, coordinator: context.coordinator)
    }

    private func requestInitialFocus(for textView: NSTextView, coordinator: Coordinator) {
        guard !coordinator.didRequestInitialFocus else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            coordinator.didRequestInitialFocus = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        var submitEnabled: Bool
        var onSubmit: () -> Void
        weak var textView: NSTextView?
        var didRequestInitialFocus = false

        init(text: Binding<String>, submitEnabled: Bool, onSubmit: @escaping () -> Void) {
            self.textBinding = text
            self.submitEnabled = submitEnabled
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = textView.string
        }

        func submit() {
            guard submitEnabled else { return }
            onSubmit()
        }
    }
}

private final class SubmitNSTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requestsNewline = modifiers.contains(.shift) || modifiers.contains(.option)

        // Let the input method consume Return while confirming marked text.
        if isReturn, !requestsNewline, !hasMarkedText() {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
