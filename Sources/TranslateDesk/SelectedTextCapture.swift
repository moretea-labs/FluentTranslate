#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import TranslateCore

/// Read the selection while its source application is still frontmost.
@MainActor
enum SelectedTextCapture {
    enum Result {
        case text(String)
        case noSelection
        case accessibilityRequired
    }

    static func capture(from application: NSRunningApplication?) async -> Result {
        guard let application else { return .noSelection }
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return .accessibilityRequired
        }
        if let selection = accessibilitySelection(pid: application.processIdentifier) {
            return .text(selection)
        }
        return await copySelectionPreservingClipboard()
    }

    private static func accessibilitySelection(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selection) == .success else { return nil }
        return normalized(selection as? String)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func copySelectionPreservingClipboard() async -> Result {
        let board = NSPasteboard.general
        let original = PasteboardSnapshot(board)
        let before = board.changeCount
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return .noSelection
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        for _ in 0..<12 {
            if Task.isCancelled {
                restoreOriginalClipboardIfStillCurrent(board, original, before)
                return .noSelection
            }
            let observedChange = board.changeCount
            if observedChange != before {
                let text = normalized(board.string(forType: .string))
                let disposition = ClipboardCapturePolicy.disposition(
                    initialChangeCount: before,
                    observedChangeCount: observedChange,
                    currentChangeCount: board.changeCount
                )
                switch disposition {
                case .waiting:
                    break
                case .captured:
                    guard original.restore(to: board, ifChangeCountMatches: observedChange) else {
                        return .noSelection
                    }
                    return text.map(Result.text) ?? .noSelection
                case .superseded:
                    // A newer clipboard write belongs to the user; preserve it and reject the capture.
                    return .noSelection
                }
            }
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
        restoreOriginalClipboardIfStillCurrent(board, original, before)
        return .noSelection
    }

    private static func restoreOriginalClipboardIfStillCurrent(
        _ board: NSPasteboard, _ original: PasteboardSnapshot, _ initialChangeCount: Int
    ) {
        let observed = board.changeCount
        guard observed != initialChangeCount else { return }
        _ = board.string(forType: .string)
        guard ClipboardCapturePolicy.shouldRestoreOriginalClipboardAfterAbort(
            initialChangeCount: initialChangeCount,
            observedChangeCount: observed,
            currentChangeCount: board.changeCount
        ) else { return }
        _ = original.restore(to: board, ifChangeCountMatches: observed)
    }

    private struct PasteboardSnapshot {
        let items: [[(NSPasteboard.PasteboardType, Data)]]

        init(_ board: NSPasteboard) {
            items = (board.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            }
        }

        @discardableResult
        func restore(to board: NSPasteboard, ifChangeCountMatches expected: Int) -> Bool {
            guard board.changeCount == expected else { return false }
            board.clearContents()
            let copies = items.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            return copies.isEmpty || board.writeObjects(copies)
        }
    }
}
#endif
